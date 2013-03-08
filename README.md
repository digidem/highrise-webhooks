# Stripe Webhooks Controller

This Sinatra application will respond to a "charge.succeeded" event from a [Stripe webhook](https://stripe.com/docs/webhooks)

Currently when receiving a POST from Stripe the app will:

1. Lookup the event on Stripe based on the ID posted

2. Only respond to "charge.succeeded" events

3. Get the customer details associated with the charge

4. Check to see whether the customer is already in Highrise (based on email address)

5. Create a new person in Highrise if needed

6. Create a new fixed price Deal in Highrise, associated with the person/donor.

7. Set the Deal to "Won"
