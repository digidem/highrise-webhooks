require 'sinatra'
require 'highrise'
require 'webhook'
require 'json'

#Set secret keys from environment variables
set :highrise_api_token, ENV['HIGHRISE_API_TOKEN']
set :webhook_path, ENV['WEBHOOK_PATH']
set :stripe_secret_key, ENV['STRIPE_SECRET_KEY']
set :highrise_group_id, 464304
set :highrise_donations_category_id, 2730561

set :protection, except: :ip_spoofing

Stripe.api_key = settings.stripe_secret_key
Highrise::Base.site = 'https://ddem.highrisehq.com'
Highrise::Base.user = settings.highrise_api_token
Highrise::Base.format = :xml

# Use an unguessable string for webhook_path for (some) added security.
post '/webhooks/stripe/' + settings.webhook_path do
  @event = Webhook::Stripe.new(request.body.read)
  
  case @event.type
  when "charge.succeeded"
    # Lookup contact in Highrise or create a new contact
    @donor = Highrise::Person.find_or_create(:email => @event.email, :name => @event.name)
  
    # Create a new Deal in Highrise for the donation, attached to the donor.
    # https://github.com/37signals/highrise-api/blob/master/sections/deals.md
    @donation = Highrise::Deal.new(
      :name => @event.description,
      :party_id => @donor.id,
      :visible_to => "NamedGroup",
      :group_id => settings.highrise_group_id,
      :price => @event.amount/100,
      :currency => "USD",
      :price_type => "fixed",
      :category_id => settings.highrise_donations_category_id
    )
    @donation.save
  
    # Deals are initially created as "Pending", since the charge/donation is already made, this is now "Won"
    @donation.update_status("won")
    content_type :json
    @donation.to_json
  end
end

post '/webhooks/paypal/' + settings.webhook_path do
  @event = Webhook::Paypal.new(request.body.read)
  
  if @event.validated?
    if @event.completed?
      # Lookup contact in Highrise or create a new contact
      @donor = Highrise::Person.find_or_create(:email => @event.email, :name => @event.name)
  
      # Create a new Deal in Highrise for the donation, attached to the donor.
      # https://github.com/37signals/highrise-api/blob/master/sections/deals.md
      @donation = Highrise::Deal.new(
        :name => @event.description,
        :party_id => @donor.id,
        :visible_to => "NamedGroup",
        :group_id => 463829,
        :price => @event.amount/100,
        :currency => "USD",
        :price_type => "fixed",
        :category_id => settings.highrise_donations_category_id
      )
      @donation.save
  
      # Deals are initially created as "Pending", since the charge/donation is already made, this is now "Won"
      @donation.update_status("won")
      content_type :json
      @donation.to_json
    end
  end
end

class Highrise::Person
  # Extend Highrise::Person with method to lookup contact via email
  # and create a new contact if it doesn't exist.
  def self.find_or_create(attributes = nil)
    # Check to see if this customer is already in Highrise (by email lookup)
    # Highrise::Person.search returns an array, we just want the first record.
    @donor = self.search(:email => attributes[:email]).first
    # If they are not in Highrise, create a new person in Highrise
    # http://stackoverflow.com/questions/11902757/getting-head-round-this-gem-api-highrise
    # https://github.com/37signals/highrise-api/blob/master/sections/people.md
    if !@donor
      @donor = self.new(
        :name => attributes[:name],
        :contact_data => {
          :email_addresses => [
            :email_address => { :address => attributes[:email] }
          ]
        }
      )
      @donor.save
    end
    @donor
  end
end