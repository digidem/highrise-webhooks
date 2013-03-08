require 'sinatra'
require 'highrise'
require 'stripe'

#Set secret keys from environment variables
set :highrise_api_token, ENV['HIGHRISE_API_TOKEN']
set :webhook_path, ENV['WEBHOOK_PATH']
set :stripe_secret_key, ENV['STRIPE_SECRET_KEY']
set :highrise_group_name, "Development"
set :highrise_group_id, 463829

set :protection, except: :ip_spoofing

Stripe.api_key = settings.stripe_secret_key
Highrise::Base.site = 'https://ddem.highrisehq.com'
Highrise::Base.user = settings.highrise_api_token
Highrise::Base.format = :xml

# Only respond to https requests
before do
  halt unless request.secure?
end

get '/' do
  "hello world"
end

# Use an unguessable string for webhook_path for (some) added security.
post '/webhooks/' + settings.webhook_path do
  
  # Stripe webhooks post JSON. Parse the JSON into event_json
  # https://stripe.com/docs/webhooks
  event_json = JSON.parse(request.body.read)
  
  # For more security, retrieve the actual event from Stripe to make sure it really exists.
  event = Stripe::Event.retrieve(event_json['id'])
  
  # Only respond to "charge.succeeded" events
  pass unless event.type == "charge.succeeded"
  
  # The charge object https://stripe.com/docs/api?lang=ruby#charges
  charge = event.data.object
  
  # Retrieve details about the Stripe customer that has been charged
  # https://stripe.com/docs/api?lang=ruby#retrieve_customer
  customer = Stripe::Customer.retrieve(charge.customer)

  # Check to see if this customer is already in Highrise (by email lookup)
  # Highrise::Person.search returns an array, we just want the first record.
  @donor = Highrise::Person.search(:email => customer.email)[0]
  
  # If they are not in Highrise, create a new person in Highrise
  # http://stackoverflow.com/questions/11902757/getting-head-round-this-gem-api-highrise
  # https://github.com/37signals/highrise-api/blob/master/sections/people.md
  if !@donor
    @donor = Highrise::Person.new(
      :name => charge.card.name,
      :contact_data => {
        :email_addresses => [
          :email_address => { :address => customer.email }
        ]
      }
    )
    @donor.save
  end
  
  # Create a new Deal in Highrise for the donation, attached to the donor.
  # https://github.com/37signals/highrise-api/blob/master/sections/deals.md
  @donation = Highrise::Deal.new(
    :name => charge.description,
    :party_id => @person.id,
    :visible_to => settings.highrise_group_name,
    :group_id => settings.highrise_group_id,
    :price => charge.amount,
    :currency => "USD",
    :price_type => "fixed",
  )
  @donation.save
  
  # Deals are initially created as "Pending", since the charge/donation is already made, this is now "Won"
  @donation.update_status("won")
  
end

    
  