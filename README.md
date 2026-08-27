# OmniAuth SHOPLINE

An OmniAuth strategy for authenticating with [SHOPLINE](https://www.shopline.com) using
its [OAuth 2.0 app authorization flow](https://developer.shopline.com/docs/apps/api-instructions-for-use/app-authorization/).

Requires Ruby >= 3.2 and OmniAuth 2.x.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'omniauth-shopline'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install omniauth-shopline

## Usage

OmniAuth 2 only accepts `POST` for the request phase. In a Rails app, add
[`omniauth-rails_csrf_protection`](https://github.com/cookpad/omniauth-rails_csrf_protection)
to your Gemfile and link to the provider with `button_to` or `link_to ..., method: :post`:

```ruby
gem 'omniauth-rails_csrf_protection'
```

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :shopline,
           'app_key', 'app_secret',
           handle: 'your-store',
           scope: 'read_products,read_orders'
end
```

`handle` is the store subdomain (`your-store` in `https://your-store.myshopline.com`) and
is required — it is what the authorize and token endpoints are addressed against. It is
read once, when the strategy is built, so serving several stores means one `provider`
entry per store.

The two positional arguments are SHOPLINE's app key and app secret. They may also be
passed by name, which takes precedence:

```ruby
  provider :shopline, handle: 'your-store', app_key: 'app_key', app_secret: 'app_secret'
```

## Auth hash

```ruby
auth = request.env['omniauth.auth']

auth['provider']               # => "shopline"
auth['credentials']['token']   # => the access token, valid for ten hours
auth['credentials']['expires_at'] # => 1762800000 (seconds since the epoch)
auth['credentials']['expires']    # => true
auth['credentials']['scope']   # => "read_products,read_orders"
auth['extra']['handle']        # => "your-store"
auth['extra']['scope']         # => "read_products,read_orders"
```

SHOPLINE's token response identifies a store, not a person, and the strategy does not set
`uid`. Key records on `extra['handle']`.

## Configuring

### The callback URL

The strategy overrides `callback_url` to drop the query string OmniAuth would otherwise
append, because SHOPLINE matches `redirectUri` against the app's registered callback URLs
exactly. Otherwise it is derived from the request, including the mount prefix — a strategy
mounted under Devise's `/users` produces
`https://app.example.com/users/auth/shopline/callback`.

Pass `redirect_uri` (or `callback_url`) to override it outright:

```ruby
  redirect_uri: 'https://app.example.com/users/auth/shopline/callback'
```

### Callback verification

SHOPLINE's authorize endpoint has no `state` parameter, so the CSRF nonce travels in
`customField`, the documented pass-through, and is checked against the session when the
callback comes back. SHOPLINE also signs the callback query string; the strategy verifies
that `sign` the way [SHOPLINE's own SDK](https://github.com/shoplineos/shopline-sdk-go/blob/main/client/sign.go)
does. Both checks are on by default and can be turned off individually:

```ruby
  verify_state: false,     # skip the customField nonce check
  verify_signature: false  # skip the `sign` check
```

`provider_ignores_state` is left at `true` on purpose: SHOPLINE never sends `state`, so
`OmniAuth::Strategies::OAuth2`'s own check can never pass. Use `verify_state` instead.

### The store host

`client_options[:site]` defaults to `https://{handle}.myshopline.com` with the placeholder
filled in from `handle`. Setting it explicitly wins, which is useful for pointing the
strategy at a proxy or a test double:

```ruby
  client_options: { site: 'https://shopline.test' }
```

## How it differs from a plain OAuth 2 strategy

Three parts of SHOPLINE's flow are not standard OAuth 2, and the strategy handles each
itself rather than inheriting it:

1. The authorize endpoint is a hash-routed admin page
   (`/admin/oauth-web/#/oauth/authorize`), so its query string sits *after* the fragment
   and cannot be built by `OAuth2::Client#authorize_url`.
2. There is no `state` parameter (see above).
3. `POST /admin/oauth/token/create` authenticates with `appkey`, `timestamp` and `sign`
   headers rather than client credentials, takes `{"code": "..."}` as its whole body, and
   answers with the token nested under `data`. SHOPLINE signs a POST over the request body
   concatenated with the millisecond timestamp — not the sorted-parameter scheme it uses
   for GETs.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run
`bundle exec rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt.

To install this gem onto your local machine, run `bundle exec rake install`.

The gemspec allows a wide dependency range, so CI also runs the suite against the oldest
versions it permits. To reproduce that locally:

    $ BUNDLE_GEMFILE=gemfiles/floor.gemfile bundle install
    $ BUNDLE_GEMFILE=gemfiles/floor.gemfile bundle exec rake spec

Run `bundle exec bundle-audit check --update` to check the locked dependency tree against
the advisory database; CI runs the same check weekly.

## Releasing

Releases are cut from the [GitHub Releases UI](https://github.com/dropstream/omniauth-shopline/releases/new);
GitHub Actions builds and publishes the gem to [rubygems.org](https://rubygems.org) via
[RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no API
key is stored in the repo and the gemspec can keep `rubygems_mfa_required`.

1. Bump `VERSION` in `lib/omniauth-shopline/version.rb` and add a `CHANGELOG.md` section
   for it, along with a link definition for the new heading at the bottom of that file.
   Commit both on `master`.
2. Draft a new release with the target set to `master` and the tag set to the version
   prefixed with `v` — `v0.1.0`, not `0.1.0`. The prefix is stripped before comparing
   against `version.rb`; the gem version itself carries no `v`.
3. Click **Generate release notes** — the preferred method — then publish. The generated
   notes list the merged pull requests; `CHANGELOG.md` carries the curated prose and
   links back to each release.

Publishing creates the tag, which fires the `Release` workflow: it reruns the full test
matrix, refuses to continue if the tag and `version.rb` disagree, and pushes the gem.
Note that RubyGems versions are immutable — a bad release can be yanked, never replaced,
so the version bump has to be committed before the release is published.

### One-time RubyGems setup

This gem has never been pushed, so the first release needs a **pending** trusted
publisher, which both claims the name `omniauth-shopline` and makes you an owner of it
once the push succeeds. On rubygems.org, open
[pending trusted publishers](https://rubygems.org/profile/oidc/pending_trusted_publishers)
-> **Create**, with:

| Field | Value |
| --- | --- |
| RubyGem name | `omniauth-shopline` |
| Repository owner | `dropstream` |
| Repository name | `omniauth-shopline` |
| Workflow filename | `release.yml` |
| Environment | `release` |

The repo also needs a GitHub environment named `release` (Settings -> Environments ->
New environment), because the publishing job runs in it.

After the first successful push the pending publisher becomes an ordinary trusted
publisher, managed from the gem's own **Trusted publishers** page. It only needs
revisiting if the gem is renamed or the repository moves.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/dropstream/omniauth-shopline.

## License

Available as open source under the terms of the [MIT License](LICENSE.txt).
