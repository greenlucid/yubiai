# Yubiai Notes

## Quick notes

Using *deal* instead of *contract* for sanity reasons.

Deal: Created by the buyer. Contains:
- buyer
- seller
- terms
- amount and token
- time for seller to provide service
- time for buyer to complain

## Good flow

Alice and Bob make a service contract offline. They agree on it.

Alice creates a deal, agreeing to send Bob 100 DAI for a crayon drawing, in a week.

The crayon drawing arrives 3 days later.

Alice is happy, and triggers the send.

Bob gets gross 100 DAI, after 10% fee he gets 90 DAI, market gets 10 DAI.

## Good flow, with haggle

Same, but Alice is unhappy. Reckons the drawing is amazing but wants a 50 DAI refund, for no reason.

Bob wants no trouble, so he complies. Bob gets gross 50 DAI, after 10% fee he gets 45 DAI, market gets 5 DAI.

## Bad flow

Alice wants 100 DAI back.

Bob won't agree, so challenge occurs.

Jurors rule to not accept 100 DAI refund. Alice can reclaim.

She now wants 50 DAI back. Etc...

### Bad flow Alice wins

Alice gets a 50 DAI refund, Bob gets gross 50 DAI.

### Bad flow Alice loses

Alice runs out of reclaims, Bob gets gross 100 DAI.

## Who pays arb fees?

Use our regular Kleros flow: Alice puts msg.value deposit equal to arb fees to make her claim, Bob does so as well. The winner gets their msg.value deposit back.
