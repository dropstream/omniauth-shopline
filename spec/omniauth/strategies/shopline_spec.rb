require 'spec_helper'

describe OmniAuth::Strategies::Shopline do
  let(:app) { lambda { |env| [200, {}, ["Hello."]] } }
  let(:strategy) { OmniAuth::Strategies::Shopline.new(app, 'app_key', 'app_secret', handle: 'test-store') }

  describe '#client_options' do
    it 'has correct site' do
      expect(strategy.client.site).to eq('https://test-store.myshopline.com')
    end

    it 'has correct authorize_url' do
      expect(strategy.client.options[:authorize_url]).to eq('/admin/oauth-web/#/oauth/authorize')
    end

    it 'has correct token_url' do
      expect(strategy.client.options[:token_url]).to eq('/admin/oauth/token/create')
    end
  end

  describe '#request_phase' do
    it 'redirects to the authorize URL' do
      allow(strategy).to receive(:callback_url).and_return('http://example.com/callback')
      expect(strategy).to receive(:redirect).with(/appKey=app_key/)
      strategy.request_phase
    end
  end

  describe 'initialization' do
    it 'raises an error if handle is not provided' do
      expect { 
        OmniAuth::Strategies::Shopline.new(app, 'app_key', 'app_secret') 
      }.to raise_error(ArgumentError, 'handle is required')
    end
  end
end