require 'omniauth-oauth2'
require 'digest'
require 'json'
require 'openssl'

module OmniAuth
  module Strategies
    class Shopline < OmniAuth::Strategies::OAuth2
      option :name, 'shopline'

      option :client_options, {
        site: 'https://{handle}.myshopline.com',
        authorize_url: '/admin/oauth-web/#/oauth/authorize',
        token_url: '/admin/oauth/token/create'
      }

      option :token_params, { grant_type: 'authorization_code' }

      def initialize(app, *args, &block)
        super
        @handle = options[:handle] || raise(ArgumentError, 'handle is required')
        options.client_options.site = "https://#{@handle}.myshopline.com"
      end

      def request_phase
        params = {
          appKey: options.app_key,
          responseType: 'code',
          scope: options.scope,
          redirectUri: callback_url
        }

        redirect client.authorize_url(params)
      end

      def callback_phase
        error = request.params['error']
        error_description = request.params['error_description']

        if error
          fail!(error.to_sym, CallbackError.new(error, error_description))
        else
          super
        end
      end

      def build_access_token
        verifier = request.params['code']
        # time must be integer with milliseconds
        timestamp = (Time.now.to_f * 1000).to_i

        # Generate signature for headers
        header_params = {
          appkey: options.app_key,
          timestamp: timestamp
        }
        signature = generate_signature(header_params)

        headers = {
          'Content-Type' => 'application/json',
          'appkey' => options.app_key,
          'timestamp' => timestamp.to_s,
          'sign' => signature
        }

        # Body only contains the authorization code
        body = { code: verifier }

        response = client.request(:post, options.client_options.token_url, {
          body: body.to_json,
          headers: headers
        })

        # Parse nested response structure: data.accessToken
        if response.parsed['data'] && response.parsed['data']['accessToken']
          ::OAuth2::AccessToken.new(
            client,
            response.parsed['data']['accessToken'],
            {
              expires_at: response.parsed['data']['expireTime'],
              scope: response.parsed['data']['scope']
            }
          )
        else
          fail!(:invalid_credentials, response.parsed)
        end
      end

      def callback_url
        options[:redirect_uri] || full_host + script_name + callback_path
      end

      extra do
        {
          'handle' => @handle,
          'scope' => access_token.params['scope']
        }
      end

      private

      # https://developer.shopline.com/docs/apps/api-instructions-for-use/generate-and-verify-signatures/?lang=en
      def generate_signature(params)
        # Sort parameters by key alphabetically (excluding sign parameter)
        sorted_params = params.reject { |k, _| k == :sign }.sort.to_h

        # Create source string from sorted parameters
        source = sorted_params.map { |k, v| "#{k}=#{v}" }.join('&')

        # Generate HMAC-SHA256 signature using helper method
        generate_hmac_sha256(source, options.app_secret)
      end

      def generate_hmac_sha256(source, secret)
        raise ArgumentError, "Source and secret must not be empty." if source.to_s.empty? || secret.to_s.empty?

        digest = OpenSSL::Digest.new('sha256')
        OpenSSL::HMAC.hexdigest(digest, secret, source)
      rescue StandardError => e
        raise "Error generating HMAC-SHA256 signature: #{e}"
        nil
      end
    end
  end
end
