# OmniAuth Shopline

This is an OmniAuth strategy for authenticating with Shopline using OAuth2.

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

Add the strategy to your `Gemfile` alongside OmniAuth:

```ruby
gem 'omniauth'
gem 'omniauth-shopline'
```

Then integrate the strategy into your middleware:

```ruby
use OmniAuth::Builder do
  provider :shopline, 'your_app_key', 'your_app_secret', {
    handle: 'your_shopline_handle',
    scope: 'read_products,read_orders'
  }
end
```

## Configuration

- `handle`: Your Shopline store handle (required)
- `scope`: Comma-separated list of permissions (optional, defaults to 'read_products')

## Auth Hash

The auth hash will contain:

```ruby
{
  provider: 'shopline',
  uid: 'user_id',
  info: {},
  credentials: {
    token: 'access_token',
    expires_at: 1234567890,
    scope: 'read_products,read_orders'
  },
  extra: {
    handle: 'your_shopline_handle',
    scope: 'read_products,read_orders'
  }
}
```

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).