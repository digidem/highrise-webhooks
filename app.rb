require 'sinatra'
require 'highrise'
require 'stripe'
require 'mail'
require 'json'

#Set secret keys from environment variables
set :highrise_api_token, ENV['HIGHRISE_API_TOKEN']
set :webhook_path, ENV['WEBHOOK_PATH']
set :stripe_secret_key, ENV['STRIPE_SECRET_KEY']
set :highrise_group_id, 463829
set :highrise_donations_category_id, 2730561

set :protection, except: :ip_spoofing

Mail.defaults do
  delivery_method :smtp, {
    :port      => 587,
    :address   => "smtp.mandrillapp.com",
    :user_name => ENV["MANDRILL_USERNAME"],
    :password  => ENV["MANDRILL_PASSWORD"]
  }
end

Stripe.api_key = settings.stripe_secret_key
Highrise::Base.site = 'https://ddem.highrisehq.com'
Highrise::Base.user = settings.highrise_api_token
Highrise::Base.format = :xml

# Use an unguessable string for webhook_path for (some) added security.
post '/webhooks/' + settings.webhook_path do
  
  # Stripe webhooks post JSON. Parse the JSON into event_json
  # https://stripe.com/docs/webhooks
  event_json = JSON.parse(request.body.read)
  
  # For more security, retrieve the actual event from Stripe to make sure it really exists.
  event = Stripe::Event.retrieve(event_json['id'])
  
  # Only respond to "charge.succeeded" events
  halt 200 unless event.type == "charge.succeeded"
  
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
  
  mail = Mail.new do
    to      customer.email
    from    'Digital Democracy <info@digital-democracy.org>' # Your from name and email address
    subject 'Thank you for your donation!'
    
    html_part do
      content_type 'text/html; charset=UTF-8'
      body "<p>Dear Donor,</p><p>Thank you so much for your kind donation of <strong>$#{charge.amount/100}</strong>. It means a lot to us.</p><p>Yours,</p><p>The Digital Democracy Team</p>"
    end
  end
  mail['X-MC-Template'] = 'test-mandrill-template|std_content00'
  mail['X-MC-Tags'] = 'test-email'
  mail['X-MC-InlineCSS'] = 'true'
  mail.deliver
  
end
