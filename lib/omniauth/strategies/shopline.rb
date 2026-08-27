# frozen_string_literal: true

require "json"
require "openssl"
require "securerandom"
require "uri"

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    # OmniAuth strategy for SHOPLINE's OAuth 2.0 app authorization flow.
    #
    # https://developer.shopline.com/docs/apps/api-instructions-for-use/app-authorization/
    #
    # SHOPLINE deviates from plain OAuth 2 in three ways that this strategy has to
    # handle itself rather than inherit:
    #
    # 1. The authorize endpoint is a hash-routed admin page, so its query string sits
    #    *after* the `#` fragment and cannot be built by `OAuth2::Client#authorize_url`.
    # 2. There is no `state` parameter. `customField` is the documented pass-through,
    #    so the CSRF nonce travels in it (see #verify_state).
    # 3. The token endpoint authenticates with `appkey`/`timestamp`/`sign` headers
    #    instead of client credentials, and signs POSTs over the request body.
    class Shopline < OmniAuth::Strategies::OAuth2
      SITE_TEMPLATE = "https://%<handle>s.myshopline.com"

      # The placeholder is replaced with the configured handle unless the consumer
      # supplies a site of their own.
      DEFAULT_SITE = "https://{handle}.myshopline.com"

      STATE_SESSION_KEY = "omniauth.shopline.state"

      option :name, "shopline"

      option :client_options, {
        site: DEFAULT_SITE,
        authorize_url: "/admin/oauth-web/#/oauth/authorize",
        token_url: "/admin/oauth/token/create"
      }

      # SHOPLINE calls these the app key and app secret. They are the OAuth2
      # client_id/client_secret positional arguments, and may also be passed by name.
      option :app_key, nil
      option :app_secret, nil

      # SHOPLINE never sends `state`, so OmniAuth::Strategies::OAuth2's own check can
      # never pass. Leave this alone and use :verify_state / :verify_signature below.
      option :provider_ignores_state, true

      # Round-trips a CSRF nonce through SHOPLINE's `customField` parameter.
      option :verify_state, true

      # Verifies the `sign` SHOPLINE appends to the callback query string.
      option :verify_signature, true

      attr_reader :handle

      def initialize(app, *args, &block)
        super

        @handle = options[:handle] || raise(ArgumentError, "handle is required")

        site = options.client_options[:site]
        return unless site.nil? || site.to_s.include?("{handle}")

        options.client_options[:site] = format(SITE_TEMPLATE, handle: @handle)
      end

      def app_key
        options.app_key || options.client_id
      end

      def app_secret
        options.app_secret || options.client_secret
      end

      # The authorize URL is built by hand: `/admin/oauth-web/#/oauth/authorize` is a
      # client-side route, so the query string belongs after the fragment. Handing the
      # path to `OAuth2::Client#authorize_url` would produce
      # `/admin/oauth-web/?appKey=...#/oauth/authorize`, which the page never reads.
      def authorize_url
        client_options = options.client_options
        query = URI.encode_www_form(authorize_params_for_shopline)

        "#{client_options[:site]}#{client_options[:authorize_url]}?#{query}"
      end

      def request_phase
        redirect authorize_url
      end

      def callback_phase
        error = request.params["error"].to_s
        unless error.empty?
          return fail!(error.to_sym, CallbackError.new(error, request.params["error_description"]))
        end

        return fail!(:csrf_detected, CallbackError.new(:csrf_detected, "CSRF detected")) unless valid_state?

        unless valid_signature?
          return fail!(:invalid_signature, CallbackError.new(:invalid_signature, "Signature verification failed"))
        end

        super
      end

      # POST /admin/oauth/token/create, authenticated by the appkey/timestamp/sign
      # headers rather than by client credentials, and answered with the token nested
      # under `data`.
      def build_access_token
        timestamp = current_timestamp
        body = JSON.generate(code: request.params["code"])

        response = client.request(
          :post,
          options.client_options[:token_url],
          body: body,
          headers: {
            "Content-Type" => "application/json",
            "appkey" => app_key.to_s,
            "timestamp" => timestamp.to_s,
            "sign" => signature_for_body(body, timestamp)
          }
        )

        access_token_from(response)
      end

      # OmniAuth::Strategy#callback_url appends the callback request's own query
      # string, which would send those params to SHOPLINE as part of redirect_uri and
      # fail the registered-URL match. Note that omniauth 2's `callback_path` already
      # carries SCRIPT_NAME, so mount prefixes must not be added again.
      def callback_url
        options[:callback_url] || options[:redirect_uri] || (full_host + callback_path)
      end

      # OmniAuth merges this with OmniAuth::Strategies::OAuth2's own credentials block
      # (token, expires_at, expires) rather than replacing it.
      credentials do
        {"scope" => access_token.params["scope"]}.compact
      end

      extra do
        {
          "handle" => handle,
          "scope" => access_token.params["scope"]
        }
      end

      private

      def authorize_params_for_shopline
        params = {
          appKey: app_key,
          responseType: "code",
          scope: options.scope,
          redirectUri: callback_url
        }

        params[:customField] = new_state if options.verify_state
        params.compact
      end

      # SHOPLINE has no `state` parameter, but `customField` is passed through to the
      # callback untouched, so it carries the nonce.
      def new_state
        state = SecureRandom.hex(24)
        session[STATE_SESSION_KEY] = state
        state
      end

      def valid_state?
        return true unless options.verify_state

        expected = session.delete(STATE_SESSION_KEY)
        !expected.to_s.empty? && secure_compare(request.params["customField"], expected)
      end

      # SHOPLINE signs the callback query the same way it signs any GET: the params
      # other than `sign`, sorted by key and joined as `k=v&k=v`.
      # https://developer.shopline.com/docs/apps/api-instructions-for-use/generate-and-verify-signatures/
      def valid_signature?
        return true unless options.verify_signature

        received = request.GET["sign"]
        return false if received.to_s.empty?

        secure_compare(received, signature_for_query(request.GET))
      end

      def access_token_from(response)
        parsed = response.parsed
        data = parsed["data"] if parsed.is_a?(Hash)
        token = data["accessToken"] if data.is_a?(Hash)

        raise ::OAuth2::Error, response if token.to_s.empty?

        ::OAuth2::AccessToken.new(
          client,
          token,
          "expires_at" => data["expireTime"],
          "scope" => data["scope"]
        )
      end

      # Milliseconds since the epoch, as SHOPLINE's `timestamp` header requires.
      def current_timestamp
        (Time.now.to_f * 1000).to_i
      end

      # SHOPLINE signs a POST over the request body concatenated with the timestamp --
      # not the sorted-parameter scheme used for GETs. The body passed here must be the
      # exact string that is sent.
      # https://github.com/shoplineos/shopline-sdk-go/blob/main/client/sign.go
      def signature_for_body(body, timestamp)
        hmac_sha256("#{body}#{timestamp}")
      end

      def signature_for_query(params)
        source = params.reject { |key, _| key.to_s == "sign" }
                       .sort_by { |key, _| key.to_s }
                       .map { |key, value| "#{key}=#{value}" }
                       .join("&")

        hmac_sha256(source)
      end

      def hmac_sha256(source)
        secret = app_secret.to_s
        raise ArgumentError, "app_secret is required to sign SHOPLINE requests" if secret.empty?

        OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, source)
      end

      def secure_compare(received, expected)
        received = received.to_s
        expected = expected.to_s
        return false unless received.bytesize == expected.bytesize

        OpenSSL.fixed_length_secure_compare(received, expected)
      end
    end
  end
end
