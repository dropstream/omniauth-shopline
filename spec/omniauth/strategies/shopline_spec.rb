# frozen_string_literal: true

RSpec.describe OmniAuth::Strategies::Shopline do
  let(:inner_app) { ->(_env) { [200, {}, ["Hello."]] } }
  let(:strategy_options) { {handle: "test-store"} }
  let(:strategy) { described_class.new(inner_app, "app_key", "app_secret", **strategy_options) }

  def app
    described_class.new(inner_app, "app_key", "app_secret", **strategy_options)
  end

  def hmac(source, secret = "app_secret")
    OpenSSL::HMAC.hexdigest("sha256", secret, source)
  end

  # SHOPLINE signs a GET (and the authorization callback) over its params, minus
  # `sign`, sorted by key and joined as `k=v&k=v`.
  def sign_query(params)
    hmac(params.reject { |key, _| key.to_s == "sign" }.sort.map { |key, value| "#{key}=#{value}" }.join("&"))
  end

  # The authorize URL's query sits after the `#` fragment, so URI#query cannot read it.
  def query_after_fragment(url)
    URI.decode_www_form(url.split("?", 2).last).to_h
  end

  def failure_message
    URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["message"]
  end

  describe "#client_options" do
    subject(:client_options) { strategy.options.client_options }

    it "derives the site from the store handle" do
      expect(client_options[:site]).to eq("https://test-store.myshopline.com")
    end

    it "has the correct authorize url" do
      expect(client_options[:authorize_url]).to eq("/admin/oauth-web/#/oauth/authorize")
    end

    it "has the correct token url" do
      expect(client_options[:token_url]).to eq("/admin/oauth/token/create")
    end

    context "when the site is overridden" do
      let(:strategy_options) { {handle: "test-store", client_options: {site: "https://proxy.example.com"}} }

      it "leaves the configured site alone" do
        expect(client_options[:site]).to eq("https://proxy.example.com")
      end
    end

    it "does not leak one store's site into another strategy instance" do
      other = described_class.new(inner_app, "app_key", "app_secret", handle: "other-store")

      expect([strategy.options.client_options[:site], other.options.client_options[:site]])
        .to eq(["https://test-store.myshopline.com", "https://other-store.myshopline.com"])
    end
  end

  describe "initialization" do
    it "raises when no handle is given" do
      expect { described_class.new(inner_app, "app_key", "app_secret") }
        .to raise_error(ArgumentError, "handle is required")
    end

    it "exposes the handle" do
      expect(strategy.handle).to eq("test-store")
    end

    it "reads the app key and secret from the positional client credentials" do
      expect([strategy.app_key, strategy.app_secret]).to eq(%w[app_key app_secret])
    end

    context "when the credentials are passed by SHOPLINE's own names" do
      let(:strategy_options) { {handle: "test-store", app_key: "named_key", app_secret: "named_secret"} }

      it "prefers app_key/app_secret" do
        expect([strategy.app_key, strategy.app_secret]).to eq(%w[named_key named_secret])
      end
    end
  end

  describe "the request phase" do
    let(:strategy_options) { {handle: "test-store", scope: "read_products,read_orders"} }
    let(:session) { {} }

    around do |example|
      previous = OmniAuth.config.request_validation_phase
      OmniAuth.config.request_validation_phase = proc {}
      example.run
      OmniAuth.config.request_validation_phase = previous
    end

    def start_request(env = {})
      post "/auth/shopline", {}, {"rack.session" => session}.merge(env)
    end

    it "redirects to the hash-routed authorize page with the query after the fragment" do
      start_request

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"])
        .to start_with("https://test-store.myshopline.com/admin/oauth-web/#/oauth/authorize?")
    end

    # OAuth2::Client#authorize_url would have produced
    # `/admin/oauth-web/?appKey=...#/oauth/authorize`, which the admin page never reads.
    it "does not push the query in front of the fragment" do
      start_request

      expect(last_response.headers["Location"]).not_to include("/admin/oauth-web/?")
    end

    it "passes the app key, response type, scope and redirect uri" do
      start_request

      expect(query_after_fragment(last_response.headers["Location"]))
        .to include(
          "appKey" => "app_key",
          "responseType" => "code",
          "scope" => "read_products,read_orders",
          "redirectUri" => "http://example.org/auth/shopline/callback"
        )
    end

    # SHOPLINE has no `state` parameter; `customField` is the documented pass-through.
    it "carries a CSRF nonce in customField and remembers it in the session" do
      start_request

      nonce = query_after_fragment(last_response.headers["Location"])["customField"]
      expect(nonce).to match(/\A[0-9a-f]{48}\z/)
      expect(session["omniauth.shopline.state"]).to eq(nonce)
    end

    context "when state verification is disabled" do
      let(:strategy_options) { {handle: "test-store", verify_state: false} }

      it "omits customField" do
        start_request

        expect(query_after_fragment(last_response.headers["Location"])).not_to have_key("customField")
      end
    end

    context "when no scope is configured" do
      let(:strategy_options) { {handle: "test-store"} }

      it "omits the scope" do
        start_request

        expect(query_after_fragment(last_response.headers["Location"])).not_to have_key("scope")
      end
    end

    # omniauth 2's `callback_path` already carries SCRIPT_NAME.
    it "keeps a mount point in the redirect uri exactly once" do
      start_request("SCRIPT_NAME" => "/users")

      expect(query_after_fragment(last_response.headers["Location"])["redirectUri"])
        .to eq("http://example.org/users/auth/shopline/callback")
    end

    context "when a redirect_uri is configured" do
      let(:strategy_options) { {handle: "test-store", redirect_uri: "https://app.example.com/shopline/callback"} }

      it "uses it verbatim" do
        start_request

        expect(query_after_fragment(last_response.headers["Location"])["redirectUri"])
          .to eq("https://app.example.com/shopline/callback")
      end
    end
  end

  describe "the callback phase" do
    let(:nonce) { "a" * 48 }
    let(:session) { {"omniauth.shopline.state" => nonce} }
    let(:token_url) { "https://test-store.myshopline.com/admin/oauth/token/create" }
    let(:token_response) do
      {
        code: 200,
        i18nCode: "SUCCESS",
        message: nil,
        data: {
          accessToken: "token123",
          expireTime: "2099-11-10T16:37:48.178+00:00",
          scope: "read_products,read_orders"
        },
        traceId: "trace"
      }
    end

    before do
      stub_request(:post, token_url).to_return(
        status: 200,
        body: token_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )
    end

    def callback_params(overrides = {})
      params = {
        "appkey" => "app_key",
        "code" => "auth_code",
        "customField" => nonce,
        "handle" => "test-store",
        "timestamp" => "1755000000000"
      }.merge(overrides)

      params.key?("sign") ? params : params.merge("sign" => sign_query(params))
    end

    def complete_callback(params = callback_params, env = {})
      get "/auth/shopline/callback?#{URI.encode_www_form(params)}", {}, {"rack.session" => session}.merge(env)
    end

    def token_request
      captured = nil
      expect(WebMock).to have_requested(:post, token_url).with { |request| captured = request }
      captured
    end

    def token_request_header(name)
      token_request.headers.find { |key, _| key.casecmp(name).zero? }&.last.to_s
    end

    it "posts only the authorization code as the request body" do
      complete_callback

      expect(token_request.body).to eq('{"code":"auth_code"}')
    end

    it "authenticates the token request with the app key and a millisecond timestamp" do
      complete_callback

      expect(token_request_header("appkey")).to eq("app_key")
      expect(token_request_header("timestamp")).to match(/\A\d{13}\z/)
      expect(token_request_header("content-type")).to eq("application/json")
    end

    # https://github.com/shoplineos/shopline-sdk-go/blob/main/client/sign.go
    it "signs the token request over the exact body concatenated with the timestamp" do
      complete_callback

      expect(token_request_header("sign"))
        .to eq(hmac("#{token_request.body}#{token_request_header("timestamp")}"))
    end

    # The sorted-parameter scheme is for GETs; signing the POST that way had SHOPLINE
    # rejecting every token exchange.
    it "does not sign the token request with the sorted-parameter scheme" do
      complete_callback

      expect(token_request_header("sign"))
        .not_to eq(hmac("appkey=app_key&timestamp=#{token_request_header("timestamp")}"))
    end

    it "builds an auth hash from the nested token payload" do
      complete_callback

      auth = last_request.env["omniauth.auth"]
      expect(auth["provider"]).to eq("shopline")
      expect(auth["credentials"]["token"]).to eq("token123")
      expect(auth["credentials"]["expires_at"]).to eq(Time.parse("2099-11-10T16:37:48.178+00:00").to_i)
      expect(auth["credentials"]["scope"]).to eq("read_products,read_orders")
      expect(auth["extra"]).to eq("handle" => "test-store", "scope" => "read_products,read_orders")
    end

    context "when the token payload carries no expireTime" do
      let(:token_response) do
        {code: 200, data: {accessToken: "token123", scope: "read_products,read_orders"}}
      end

      it "reports a token that does not expire" do
        complete_callback

        credentials = last_request.env["omniauth.auth"]["credentials"]
        expect(credentials["token"]).to eq("token123")
        expect(credentials["expires"]).to be(false)
      end
    end

    describe "state verification" do
      it "fails when customField does not match the session nonce" do
        complete_callback(callback_params("customField" => "b" * 48))

        expect(failure_message).to eq("csrf_detected")
      end

      it "fails when customField is missing" do
        params = callback_params.reject { |key, _| key == "customField" }

        complete_callback(params.merge("sign" => sign_query(params)))

        expect(failure_message).to eq("csrf_detected")
      end

      it "fails when the session has no nonce" do
        session.clear

        complete_callback

        expect(failure_message).to eq("csrf_detected")
      end

      it "consumes the nonce so a callback cannot be replayed" do
        complete_callback

        expect(session).not_to have_key("omniauth.shopline.state")
      end

      context "when state verification is disabled" do
        let(:strategy_options) { {handle: "test-store", verify_state: false} }

        it "accepts a callback with no customField" do
          params = callback_params.reject { |key, _| key == "customField" }

          complete_callback(params.merge("sign" => sign_query(params)))

          expect(last_request.env["omniauth.auth"]["credentials"]["token"]).to eq("token123")
        end
      end
    end

    describe "signature verification" do
      it "fails when the signature does not match the query" do
        complete_callback(callback_params("sign" => hmac("tampered")))

        expect(failure_message).to eq("invalid_signature")
      end

      it "fails when the signature is missing" do
        complete_callback(callback_params("sign" => ""))

        expect(failure_message).to eq("invalid_signature")
      end

      it "fails when a signed parameter was tampered with" do
        params = callback_params
        complete_callback(params.merge("code" => "someone_elses_code"))

        expect(failure_message).to eq("invalid_signature")
      end

      it "verifies signatures over parameters it does not otherwise use" do
        complete_callback(callback_params("lang" => "en"))

        expect(last_request.env["omniauth.auth"]["credentials"]["token"]).to eq("token123")
      end

      context "when signature verification is disabled" do
        let(:strategy_options) { {handle: "test-store", verify_signature: false} }

        it "accepts an unsigned callback" do
          params = callback_params.reject { |key, _| key == "sign" }

          complete_callback(params)

          expect(last_request.env["omniauth.auth"]["credentials"]["token"]).to eq("token123")
        end
      end
    end

    describe "failures" do
      it "passes a provider error through" do
        params = callback_params("error" => "access_denied", "error_description" => "Merchant declined")

        complete_callback(params.merge("sign" => sign_query(params)))

        expect(failure_message).to eq("access_denied")
      end

      it "fails when the token payload carries no access token" do
        stub_request(:post, token_url).to_return(
          status: 200,
          body: {code: 40_000, i18nCode: "INVALID_CODE", message: "code expired"}.to_json,
          headers: {"Content-Type" => "application/json"}
        )

        complete_callback

        expect(failure_message).to eq("invalid_credentials")
      end

      it "fails when the token endpoint returns an error status" do
        stub_request(:post, token_url).to_return(status: 400, body: "Bad Request")

        complete_callback

        expect(failure_message).to eq("invalid_credentials")
      end
    end
  end

  describe "#callback_url" do
    subject(:callback_url) { strategy.callback_url }

    before { strategy.instance_variable_set(:@env, Rack::MockRequest.env_for("http://app.example.com/auth/shopline/callback?code=abc")) }

    it "drops the callback request's own query string" do
      expect(callback_url).to eq("http://app.example.com/auth/shopline/callback")
    end

    context "when redirect_uri is configured" do
      let(:strategy_options) { {handle: "test-store", redirect_uri: "https://app.example.com/shopline"} }

      it "uses the configured value" do
        expect(callback_url).to eq("https://app.example.com/shopline")
      end
    end

    context "when callback_url is configured" do
      let(:strategy_options) { {handle: "test-store", callback_url: "https://app.example.com/explicit"} }

      it "uses the configured value" do
        expect(callback_url).to eq("https://app.example.com/explicit")
      end
    end
  end
end
