require 'rubygems'
require 'uri'
require 'json'
require 'net/http'
require 'net/https'
require 'cgi'

=begin
helps you make API calls to the InKomerce API V1
=end

module InKomerceAPIV1

SITES = {
  test: 'http://new-host:3001/',
  production: 'https://app.inkomerce.com/',
}

  class TokenGenerator
    def initialize(client_id,client_secret,site_type = :production)
      @url = URI.parse(SITES[site_type] + 'oauth/token')
      @url.query = "client_id=#{client_id}&client_secret=#{client_secret}&grant_type=client_credentials"
    end
    
    def token
      path = @url.path + '?' + @url.query
      call = Net::HTTP::Get.new(path)
      
      response = Net::HTTP.start(@url.host, @url.port, use_ssl: (@url.scheme=='https')) {
        |http| http.request(call)
      }

      JSON.parse(response.body).deep_symbolize_keys
    end
  end

  class Connector
    
    attr_accessor :token
    attr_accessor :site_type
    
    def symbolize_return_record_keys(rec)
      if rec.is_a?(Array)
        rec.map { |item| symbolize_return_record_keys(item) }
      elsif rec.is_a?(Hash)
        Hash[rec.symbolize_keys.map { |item| [item[0].to_sym, symbolize_return_record_keys(item[1])]}]
      else
        rec
      end
    end
    
    def initialize(site_type = :production,token=nil)
      @api_endpoint = SITES[site_type] + 'api/v1'
      self.site_type = site_type
      self.token = token
    end
  
    # make a call to the InKomerce API
    def call(call, method = :get, params = false)
      # get the url
      url = URI.parse(@api_endpoint + call)
      
      send_xml = params.is_a?(Hash) && params.delete(:send_xml)
      send_format = send_xml ? 'xml' : 'json'
      
      case method
      when :get
        url.query = params.keys.map { |key| "#{key}=#{params[key]}"}.join('&') if params.is_a?(Hash)
        path = url.path
        path += '?' + url.query if url.query
        p "INKAPI:GET #{path}"
        call = Net::HTTP::Get.new(path)
      when :post
        p "INKAPI:POST #{url.path}"
        call = Net::HTTP::Post.new(url.path, {'Content-Type' => "application/#{send_format}", 'User-Agent' => 'InKomerce API Ruby SDK'})
        p send_format
        if params
          call.body = send_xml ? params.to_xml : params.to_json
        end
      when :put
        p "INKAPI:PUT #{url.path}"
        call = Net::HTTP::Put.new(url.path, {'Content-Type' => "application/#{send_format}", 'User-Agent' => 'InKomerce API Ruby SDK'})
        if params
          call.body = send_xml ? params.to_xml : params.to_json
        end
      when :delete
        url.query = params.keys.map { |key| "#{key}=#{params[key]}"}.join('&') if params.is_a?(Hash)
        path = url.path
        path += '?' + url.query if url.query
        p "INKAPI:DELETE #{path}"
        call = Net::HTTP::Delete.new(path)
      end
      
      if @token
        call.add_field('authorization',"Bearer token=#{@token}")
      end
      
      # create the request object
      response = Net::HTTP.start(url.host, url.port, use_ssl: (url.scheme=='https')) {
        |http| http.request(call)
      }
      # returns JSON response as ruby hash
      symbolize_return_record_keys(JSON.parse(response.body))
    end
    
    def api_call(path,method,params,add_params)
      params.stringify_keys!
      add_params.stringify_keys! if add_params.is_a?(Hash)
      path.gsub!(/\(([^:]*):([^)]+)\)/) { params.key?($2) ? $1+params[$2] : add_params && add_params.key?($2) ? $1+add_params[$2] : '' }
      path.gsub!(/:([^\/]+)/) { params[$1] or (add_params and add_params[$1]) or raise "ERROR: Missing parameter #{$1}" }
      call(path,method,add_params)
    end
  end
  
    
  class Global < Connector
    
    def initialize(site_type = :production)
      super(site_type)
    end
    
    ###################################################################################
    # get_categories: Returns list of all categories
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    search (Optional,String): Put part of the category name and all matching categories will be returned
    #
    ###################################################################################
    def get_categories(add_params = nil)
      params = {
      }
      api_call('/global/categories(.:format)',:get,params,add_params)
    end
    
    ###################################################################################
    # get_currencies: Get list of all currnecies supported by InKomerce
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    country (Optional,String): Put part of the country name and all matching currencies will be returned
    #    country_code (Optional,String): Find currency by country code (two letters)
    #
    # Note: country and country_code are mutual exclusive (cannot be used together)
    ###################################################################################
    def get_currencies(add_params = nil)
      params = {
      }
      api_call('/global/currencies(.:format)',:get,params,add_params)
    end

  
    ###################################################################################
    # get_image_url: Get an image url
    #
    # Parameters:
    #    id (Integer): The image id to get the urls for
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    style (Optional,String): The style of the image. Use '*' or 'all' for all images (or just don't set)
    #
    ###################################################################################
    def get_image_url(id, add_params = nil)
      params = {
        id: id,
      }
      api_call('/global/images/:id/url(.:format)',:get,params,add_params)
    end

  end

  class ConversationProxy < Connector

    attr_accessor :uid
    attr_accessor :conversation_proxy_rec

    def initialize(token,site_type = :production)
      super(site_type,token)
    end

    ##########################################################################################################
    #
    # Connect to an existing Conversation proxy
    #
    # Parameters:
    #   uid: The unique id of the Conversation proxy
    #   token: The token of the Conversation proxy
    #   site_type: :production or :test (defaults to :production)
    ##########################################################################################################
    def self.connect(uid,token,site_type = :production)
      conversation_proxy = new(token,site_type)
      conversation_proxy.uid = uid
      conversation_proxy.load
    end

    def load(rec=nil)
      self.conversation_proxy_rec = rec || get
      self
    end
    
    ##################################################################################
    # Perform all create actions (including getting the token)
    #
    # Parameters:
    #   client_id (String): The id of the client (obtainable from the inkomerce partner back-office)
    #   client_secret (String): The secret of the site obtained from he inkomerce partner back-office
    #   site_type (Symbol): :production or :test
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): A name for the proxy
    #    notification_mode (Optional,String): The notification mode that will be used by the app. When using push notification, poll is also allowed.
    #    webhook (Optional,String): The webhook url (must be given when notification_mode is 'push'
    #    logo_uri (Optional,String): The uri/url for the the app logo. Use empty string to erase the logo.
    #
    ###################################################################################
    def self.create(client_id,client_secret,site_type,add_params)
      token_rec = InKomerceAPIV1::TokenGenerator.new(client_id,client_secret,site_type).token
      if token_rec.key?(:error)
        raise token_rec[:error]
      end
      unless token_rec.key?(:access_token)
        raise "Missing token!"
      end
      create_by_token(token_rec[:access_token],site_type,add_params)
    end
    
    ##################################################################################
    # Creates a conversation_proxy from a token, either a token that was generated by the client_id
    # and client_secret or token that was aquired by create_affinity
    #
    # Note: In case of token that was aquired by create_affinity, the store will be created under
    #       the partner user account and not the affiliated user account!
    #
    # Parameters:
    #   token (String): The client/affinity token recieved by the token generator or create_affinity calls
    #   site_type (Symbol): :production or :test
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): A name for the proxy
    #    notification_mode (Optional,String): The notification mode that will be used by the app. When using push notification, poll is also allowed.
    #    webhook (Optional,String): The webhook url (must be given when notification_mode is 'push'
    #    logo_uri (Optional,String): The uri/url for the the app logo. Use empty string to erase the logo.
    #
    #######################################################################################
    def self.create_by_token(token,site_type,add_params)
      conversation_proxy = new(token,site_type)
      record = conversation_proxy.send(:create,add_params)
      puts "conversation_proxy_rec: #{record}\n"
      unless record.key?(:conversation_proxy) && record[:conversation_proxy].key?(:uid)
        if record[:error]
          raise record[:error]
        else
          raise "Unable to create store!"
        end
      end
      conversation_proxy.conversation_proxy_rec = record
      conversation_proxy.uid = record[:conversation_proxy][:uid]
      conversation_proxy
    end


    ###################################################################################
    # token: Automatically generates a new conversation_proxy token and replaces it
    #
    # Parameters:
    #   client_id (String): The id of the client (obtainable from the inkomerce partner back-office)
    #   client_secret (String): The secret of the site obtained from he inkomerce partner back-office
    #
    ###################################################################################
    def replace_token(client_id,client_secret)
      token_rec = InKomerceAPIV1::TokenGenerator.new(client_id,client_secret,site_type).token
      if token_rec.key?(:error)
        raise "#{token_rec[:error]}"
      end
      unless token_rec.key?(:access_token)
        raise "Missing token!"
      end
      new_token(new_token: token_rec[:access_token])
    end
  
    ###################################################################################
    # new_token: Change conversation_proxy token (use if token compromised)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    new_token (Required,String): The new token (obtained through the oauth system)
    #
    ###################################################################################
    def new_token(add_params = nil)
      params = {
        uid: uid,
      }
      # This is a modification from the autogenerated file
      # Update the token according to the returned value
      ret = api_call('/conversation_proxies/:uid/token(.:format)',:post,params,add_params)
      if ret.key?(:token) && ret[:token].key?(:token)
        self.token = ret[:token][:token]
      end
      ret
    end


    ###################################################################################
    # update: Update the conversation proxy
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Optional,String): The name of the conversation proxy
    #    notification_mode (Optional,String): The notification mode that will be used by the app. When using push notification, poll is also allowed.
    #    webhook (Optional,String): The webhook url (must be given when notification_mode is 'push'
    #    logo_uri (Optional,String): The uri/url for the the app logo. Use empty string to erase the logo.
    #
    ###################################################################################
    def update(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/conversation_proxies/:uid(.:format)',:put,params,add_params)
    end


    ###################################################################################
    # get: Get the current user proxy
    #
    ###################################################################################
    def get(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/conversation_proxies/:uid(.:format)',:get,params,add_params)
    end


    ###################################################################################
    # create_affinity: Create or get a user affiliation
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    token (Optional,String): A token number for a user that was provided by InKomerce user authentication system
    #    email_address (Optional,String): An email address that can be used to identify the user
    #    name (Optional,String): Used to add a descriptive user name when it does not exists (relevant only to email_address)
    #
    ###################################################################################
    def create_affinity(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/conversation_proxies/:uid/affinities(.:format)',:post,params,add_params)
    end


    ###################################################################################
    # initiate_negotiation: Initiate a buyer negotiation
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    kind (Optional,String): The kind of negotiation (sell or buy), buy is the default
    #    user_affinity_token (Required,String): The user affinity token of the user that is going to initiate the negotiation
    #    buid (Required,String): The buselftton unique id for the product that is being negotiated for
    #    initial_bid (Optional,String): The initial bid that is offered to the seller
    #
    ###################################################################################
    def initiate_negotiation(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/conversation_proxies/:uid/negotiations/initiate(.:format)',:post,params,add_params)
    end


    ###################################################################################
    # get_negotiations: Get all negotiations
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    kind (Optional,String): The kind of negotiation (sell or buy), buy is the default
    #    all (Optional,Virtus::Attribute::Boolean): Take both active and non active negotiations!
    #
    ###################################################################################
    def get_negotiations(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/conversation_proxies/:uid/negotiations(.:format)',:get,params,add_params)
    end


    ###################################################################################
    # get_negotiation: Get the current negotiation status
    #
    # Parameters:
    #    nuid (String): The negotiation id
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    kind (Optional,String): The kind of negotiation (sell or buy), buy is the default
    #
    ###################################################################################
    def get_negotiation(nuid, add_params = nil)
      params = {
      uid: uid,
      nuid: nuid,
      }
      api_call('/conversation_proxies/:uid/negotiations/:nuid(.:format)',:get,params,add_params)
    end


    ###################################################################################
    # get_negotiation_poll: Poll messages for the current negotiation
    #
    # Parameters:
    #    nuid (String): The negotiation id
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    kind (Optional,String): The kind of negotiation (sell or buy), buy is the default
    #    last_id (Optional,Integer): The id of the last message that was polled. If not set, it will use the internall stored last_id
    #
    ###################################################################################
    def get_negotiation_poll(nuid, add_params = nil)
      params = {
      uid: uid,
      nuid: nuid,
      }
      api_call('/conversation_proxies/:uid/negotiations/:nuid/poll(.:format)',:get,params,add_params)
    end


    ###################################################################################
    # do_negotiation: Perform a transition on the negotiation (ex: bid, accept, checkout etc...)
    #
    # Parameters:
    #    nuid (String): The negotiation id
    #    transition (String): The transition to perform. Must be one of the transitions that are available.
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    kind (Optional,String): The kind of negotiation (sell or buy), buy is the default
    #    bid (Optional,String): The bid to perform (required for some of the transitions)
    #
    ###################################################################################
    def do_negotiation(nuid, transition, add_params = nil)
      params = {
      uid: uid,
      nuid: nuid,
      transition: transition,
      }
      api_call('/conversation_proxies/:uid/negotiations/:nuid/:transition(.:format)',:put,params,add_params)
    end


  protected

    ###################################################################################
    # create: Create a conversation proxy
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): A name for the proxy
    #    notification_mode (Optional,String): The notification mode that will be used by the app. When using push notification, poll is also allowed.
    #    webhook (Optional,String): The webhook url (must be given when notification_mode is 'push'
    #    logo_uri (Optional,String): The uri/url for the the app logo. Use empty string to erase the logo.
    #
    ###################################################################################
    def create(add_params = nil)
      params = {
      }
      api_call('/conversation_proxies(.:format)',:post,params,add_params)
    end



  end


  class Store < Connector
    
    attr_accessor :store_rec
    attr_accessor :uid
    
    ##################################################################################
    # Perform all create actions (including getting the token)
    #
    # Parameters:
    #   client_id (String): The id of the client (obtainable from the inkomerce partner back-office)
    #   client_secret (String): The secret of the site obtained from the inkomerce partner back-office
    #   site_type (Symbol): :production or :test
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): The name of the store
    #    default_category_id (Required,Integer): The global default category of the store
    #    store_url (Required,String): The store url
    #    success_uri (Required,String): The success uri of the store (can be relative to store url or full url)
    #    cancel_uri (Required,String): The cancel uri of the store (can be relative to store url or full url)
    #    currency (Required,String): The default currency of the store
    #    locale (Required,String): The locale keyword of the store
    #    logo_uri (Optional,String): A URL of the store logo image
    #
    #######################################################################################
    def self.create(client_id,client_secret,site_type,add_params)
      token_rec = InKomerceAPIV1::TokenGenerator.new(client_id,client_secret,site_type).token
      if token_rec.key?(:error)
        raise "#{token_rec[:error]}"
      end
      unless token_rec.key?(:access_token)
        raise "Missing token!"
      end
      create_by_token(token_rec[:access_token],site_type,add_params)
    end
    
    ##################################################################################
    # Creates a store from a token, either a token that was generated by the client_id
    # and client_secret or token that was aquired by create_affinity
    #
    # Note: In case of token that was aquired by create_affinity, the store will be created under
    #       the partner user account and not the affiliated user account!
    #
    # Parameters:
    #   token (String): The client/affinity token recieved by the token generator or create_affinity calls
    #   site_type (Symbol): :production or :test
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): The name of the store
    #    default_category_id (Required,Integer): The global default category of the store
    #    store_url (Required,String): The store url
    #    success_uri (Required,String): The success uri of the store (can be relative to store url or full url)
    #    cancel_uri (Required,String): The cancel uri of the store (can be relative to store url or full url)
    #    currency (Required,String): The default currency of the store
    #    locale (Required,String): The locale keyword of the store
    #    logo_uri (Optional,String): A URL of the store logo image
    #
    #######################################################################################
    def self.create_by_token(token,site_type,add_params)
      store = new(token,site_type)
      store_rec = store.send(:create,add_params)
      puts "store_rec: #{store_rec}\n"
      unless store_rec.key?(:store) && store_rec[:store].key?(:uid)
        if store_rec[:error]
          raise store_rec[:error]
        else
          raise "Unable to create store!"
        end
      end
      store.store_rec = store_rec
      store.uid = store_rec[:store][:uid]
      store
    end
    
    ##########################################################################################################
    #
    # Connect to an existing store
    #
    # Parameters:
    #   uid: The unique id of the store
    #   token: The token of the store
    #   site_type: :production or :test (defaults to :production)
    ##########################################################################################################
    def self.connect(uid,token,site_type = :production)
      store = new(token,site_type)
      store.uid = uid
      store.load
    end

    def load(rec=nil)
      self.store_rec = rec || get
      self
    end

    
    def initialize(token,site_type = :production)
      super(site_type,token)
    end
  
  
    ###################################################################################
    # token: Automatically generates a new store token and replaces it
    #
    # Parameters:
    #   client_id (String): The id of the client (obtainable from the inkomerce partner back-office)
    #   client_secret (String): The secret of the site obtained from he inkomerce partner back-office
    #
    ###################################################################################
    def replace_token(client_id,client_secret)
      token_rec = InKomerceAPIV1::TokenGenerator.new(client_id,client_secret,site_type).token
      if token_rec.key?(:error)
        raise "#{token_rec[:error]}"
      end
      unless token_rec.key?(:access_token)
        raise "Missing token!"
      end
      new_token(new_token: token_rec[:access_token])
    end
  
    ###################################################################################
    # new_token: Change store token (use if token compromised)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    new_token (Required,String): The new token (obtained through the oauth system)
    #
    ###################################################################################
    def new_token(add_params = nil)
      params = {
        uid: uid,
      }
      # This is a modification from the autogenerated file
      # Update the token according to the returned value
      ret = api_call('/stores/:uid/token(.:format)',:post,params,add_params)
      if ret.key?(:token) && ret[:token].key?(:token)
        self.token = ret[:token][:token]
      end
      ret
    end
  
  
    ###################################################################################
    # update: Update the store
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Optional,String): The name of the store
    #    default_category_id (Optional,Integer): The global default category of the store
    #    store_url (Optional,String): The store url
    #    success_uri (Optional,String): The success uri of the store (can be relative to store url or full url)
    #    cancel_uri (Optional,String): The cancel uri of the store (can be relative to store url or full url)
    #    currency (Optional,String): The default currency of the store
    #    locale (Optional,String): The locale keyword of the store
    #    logo_uri (Optional,String): A URL of the store logo image
    #
    ###################################################################################
    def update(add_params = nil)
      params = {
        uid: uid,
      }
      api_call('/stores/:uid(.:format)',:put,params,add_params)
    end
  
  
    ###################################################################################
    # get: Get the store info
    #
    ###################################################################################
    def get(add_params = nil)
      params = {
        uid: uid,
      }
      api_call('/stores/:uid(.:format)',:get,params,add_params)
    end
    
  
    ###################################################################################
    # get_taxonomies: Get taxonomies of the store
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    search (Optional,String): Put part of the taxonomy name and all matching taxonomies will be returned
    #
    ###################################################################################
    def get_taxonomies(add_params = nil)
      params = {
        uid: uid,
      }
      api_call('/stores/:uid/taxonomies(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # get_taxonomy: Get the taxonomy
    #
    # Parameters:
    #    rid (String): The texonomy id in your store
    #
    ###################################################################################
    def get_taxonomy(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/taxonomies/:rid(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # create_taxonomy: Set the taxonomy
    #
    # Parameters:
    #    rid (String): The texonomy id in your store
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): The name of the taxonomy
    #    parent_rid (Optional,String): The parent rid
    #    sons_rids (Optional,String): A commam seperated list of the sons rids
    #    category_id (Optional,Integer): The global category id linked to the taxonomy
    #
    ###################################################################################
    def create_taxonomy(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/taxonomies/:rid(.:format)',:post,params,add_params)
    end
  
  
    ###################################################################################
    # get_products: Returns list of all products for the store
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    what (Optional,String): What should be retrieved on all product. Available options: "rid" , "burl" (button url,the default), "short" or "long"
    #    category_id (Optional,Integer): Get only products that belong to certain global category
    #    taxonomy_rid (Optional,String): Get only products that belong to a certain taxonomy
    #
    ###################################################################################
    def get_products(add_params = nil)
      params = {
        uid: uid,
      }
      api_call('/stores/:uid/products(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # create_product: Create a new product
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    rid (Required,String): The remote store id of the product (must be unique)
    #    title (Required,String): A short title for the procduct
    #    description (Required,String): The description of the product
    #    offer (Required,String): The initial offer
    #    minimum_price (Optional,String): The minimum price that accepts for the product
    #    category_id (Optional,Integer): The category id that the product belongs to (global ink categories)
    #    taxonomies_rids (Optional,String): The taxonomies of the product (optional)
    #    sku (Optional,String): The sku (or any other seller's internal identification number). Must be unique!
    #    images_urls (Optional,Array): List of image urls to add to the gallery (it will download the images from the urls)
    #    allow_override (Optional,Virtus::Attribute::Boolean): Wheather to allow overriding of existing product
    #
    ###################################################################################
    def create_product(add_params = nil)
      params = {
        uid: uid,
      }
      api_call('/stores/:uid/products(.:format)',:post,params,add_params)
    end
  
  
    ###################################################################################
    # get_product: Get the product's details
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    what (Optional,String): What should be retrieved on all product. Available options: "burl" (button url, default), "short" or "long"
    #
    ###################################################################################
    def get_product(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/products/:rid(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # update_product: Update product
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    title (Optional,String): A short title for the procduct
    #    description (Optional,String): The description of the product
    #    offer (Optional,String): The initial offer
    #    minimum_price (Optional,String): The minimum price that accepts for the product
    #    category_id (Optional,Integer): The category id that the product belongs to (global ink categories)
    #    taxonomies_rids (Optional,String): The taxonomies of the product (optional)
    #    sku (Optional,String): The sku (or any other seller's internal identification number). Must be unique!
    #    images_urls (Optional,Array): List of image urls to add to the gallery (it will download the images from the urls)
    #
    ###################################################################################
    def update_product(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/products/:rid(.:format)',:put,params,add_params)
    end
  
  
    ###################################################################################
    # get_product_images: Get list of all images
    #
    # Parameters:
    #    rid (General): The remote store id of the product (must be unique)
    #
    ###################################################################################
    def get_product_images(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/products/:rid/images(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # upload_product_image: Upload an image
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #    file_name (String): The file name to upload from (in the local file system)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    title (Optional,String): The title of the image
    #
    ###################################################################################
    def upload_product_image(rid, file_name, add_params = {})
      p_name = File.basename(file_name)
      fh = File.open(file_name,'r')
      file = {
        :filename => p_name,
        :content => Base64.encode64(fh.read)
      }
      params = {
        uid: uid,
        rid: rid,
      }
      add_params[:file] = file
      add_params[:send_xml] = true
      api_call('/stores/:uid/products/:rid/images/upload(.:format)',:post,params,add_params)
    end
  
  
    ###################################################################################
    # upload_url_product_image: Upload image (from url to ink)
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    url (Required,String): The url from which to upload the image
    #    title (Optional,String): The tital of the image
    #
    ###################################################################################
    def upload_url_product_image(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/products/:rid/images/upload_url(.:format)',:post,params,add_params)
    end
  
  
    ###################################################################################
    # get_product_image: Get an image url (to be used to show the image)
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #    id (Integer): The id of the image
    #    style (String): small_thumb|thumb|listing_thumb|large|all (all means all styles url)
    #
    ###################################################################################
    def get_product_image(rid, id, style, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
        id: id,
        style: style,
      }
      api_call('/stores/:uid/products/:rid/images/:id/:style(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # delete_product_image: Delete an image
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #    id (Integer): The id of the image
    #
    ###################################################################################
    def delete_product_image(rid, id, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
        id: id,
      }
      api_call('/stores/:uid/products/:rid/images/:id(.:format)',:delete,params,add_params)
    end
  
  
    ###################################################################################
    # reorder_product_image: Reorder images
    #
    # Parameters:
    #    rid (String): The remote store id of the product (must be unique)
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    order (Required,Array): List of ids of images according to new order
    #
    ###################################################################################
    def reorder_product_image(rid, add_params = nil)
      params = {
        uid: uid,
        rid: rid,
      }
      api_call('/stores/:uid/products/:rid/images/reorder(.:format)',:post,params,add_params)
    end
  
  
    ###################################################################################
    # get_button_product: Get the button's product
    #
    # Parameters:
    #    buid (String): The button unique id
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    what (Optional,String): What should be retrieved on all product. Available options: "rid" just the pids, "short" (the default) or "long"
    #
    ###################################################################################
    def get_button_product(buid, add_params = nil)
      params = {
        uid: uid,
        buid: buid,
      }
      api_call('/stores/:uid/buttons/:buid/product(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # get_button_cans: Get all negotiations for a button (with state)
    #
    # Parameters:
    #    buid (String): The button unique id
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    state (Optional,String): Filter by state of negotiation
    #
    ###################################################################################
    def get_button_cans(buid, add_params = nil)
      params = {
        uid: uid,
        buid: buid,
      }
      api_call('/stores/:uid/buttons/:buid/cans(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # get_store_button_can: Get a negotiation information (may depend on the state of the negotiation)
    #
    # Parameters:
    #    buid (String): The button uid
    #    nuid (String): The negotiation uid
    #
    ###################################################################################
    def get_store_button_can(buid, nuid, add_params = nil)
      params = {
        uid: uid,
        buid: buid,
        nuid: nuid,
      }
      api_call('/stores/:uid/buttons/:buid/cans/:nuid(.:format)',:get,params,add_params)
    end
  
  
    ###################################################################################
    # close_store_button_can: Close a negotiation (mark it as completed)
    #
    # Parameters:
    #    buid (String): The button uid
    #    nuid (String): The negotiation uid
    #
    ###################################################################################
    def close_store_button_can(buid, nuid, add_params = nil)
      params = {
        uid: uid,
        buid: buid,
        nuid: nuid,
      }
      api_call('/stores/:uid/buttons/:buid/cans/:nuid/close(.:format)',:post,params,add_params)
    end

    protected
  
    ###################################################################################
    # create: Create a store
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    name (Required,String): The name of the store
    #    default_category_id (Required,Integer): The global default category of the store
    #    store_url (Required,String): The store url
    #    success_uri (Required,String): The success uri of the store (can be relative to store url or full url)
    #    cancel_uri (Required,String): The cancel uri of the store (can be relative to store url or full url)
    #    currency (Required,String): The default currency of the store
    #    locale (Required,String): The locale keyword of the store
    #
    ###################################################################################
    def create(add_params = nil)
      params = {
      }
      api_call('/stores(.:format)',:post,params,add_params)
    end



  end

  class PartnerProxy < Connector

    attr_accessor :uid
    attr_accessor :partner_record

    def initialize(token,site_type = :production)
      super(site_type,token)
    end

    ##########################################################################################################
    #
    # Connect to an existing Partner proxy
    #
    # Parameters:
    #   uid: The unique id of the Partner proxy
    #   token: The token of the Partner proxy
    #   site_type: :production or :test (defaults to :production)
    #
    ##########################################################################################################
    def self.connect(uid,token,site_type = :production)
      partner_proxy = new(token,site_type)
      partner_proxy.uid = uid
      partner_proxy.load
    end

    def load
      self.partner_record = get
      self
    end

    ##################################################################################
    #
    # Perform all authentication action
    #
    # Parameters:
    #   uid: The unique identifier of the partner (received by email)
    #   client_id (String): The id of the client (obtainable from the inkomerce seller back-office)
    #   client_secret (String): The secret of the site obtained from he inkomerce seller back-office
    #   site_type (Symbol): :production or :test
    #
    ###################################################################################
    def self.authenticate(uid,client_id,client_secret,site_type,add_params=nil)
      token_rec = InKomerceAPIV1::TokenGenerator.new(client_id,client_secret,site_type).token
      if token_rec.key?(:error)
        raise token_rec[:error]
      end
      unless token_rec.key?(:access_token)
        raise "Missing token!"
      end
      partner_proxy = new(token_rec[:access_token],site_type)
      self.uid = uid
      record = partner_proxy.send(:authenticate,add_params)
      unless record.key?(:partner)
        if record[:error]
           raise record[:error]
        else
          raise 'Unable to create Partner proxy!'
        end
      end
      partner_proxy.partner_record = record
      partner_proxy
    end

    ###################################################################################
    # get: Get your partner account's details
    #
    ###################################################################################
    def get(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/partner_proxies/:uid(.:format)',:get,params,add_params)
    end


    ###################################################################################
    # create_affinity: Create or get a user affiliation
    #
    # Hashed Parameters: (pass to the add_params hash)
    #    token (Optional,String): A token number for a user that was provided by InKomerce user authentication system
    #    email_address (Optional,String): An email address that can be used to identify the user
    #    name (Optional,String): Used to add a descriptive user name when it does not exists (relevant only to email_address)
    #
    ###################################################################################
    def create_affinity(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/partner_proxies/:uid/affinities(.:format)',:post,params,add_params)
    end


  protected

    ###################################################################################
    # authenticate: Authenticate your partner account
    #
    ###################################################################################
    def authenticate(add_params = nil)
      params = {
      uid: uid,
      }
      api_call('/partner_proxies/:uid/authenticate(.:format)',:post,params,add_params)
    end



  end



    
end
