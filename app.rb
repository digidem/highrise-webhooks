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

Webhook::Stripe.api_key = settings.stripe_secret_key
Highrise::Base.site = 'https://ddem.highrisehq.com'
Highrise::Base.user = settings.highrise_api_token
Highrise::Base.format = :xml

# Use an unguessable string for webhook_path for (some) added security.
post '/webhooks/stripe/' + settings.webhook_path do
  @event = Webhook::Stripe.new(request.body.read)
  case @event.type
  when "charge.succeeded"
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
      :party_id => @donor.id,
      :visible_to => "NamedGroup",
      :group_id => settings.highrise_group_id,
      :price => charge.amount/100,
      :currency => "USD",
      :price_type => "fixed",
      :category_id => settings.highrise_donations_category_id
    )
    @donation.save
  
    # Deals are initially created as "Pending", since the charge/donation is already made, this is now "Won"
    @donation.update_status("won")
  end
end
