# Yubiai Guide

## Bob creates an offer

### What Bob sees

Note: In this example, we assume minimum UBI burner fee to be 1%.

Bob goes to the website and publishes an offer to draw crayon drawings:

- He will deliver the service in 1 week.
- After the service, he grants 3 days for complaints and refunds.
- He wants 100 WXDAI for this service.
- He will take an extra 4% fee to burn UBI.
- He submits three pictures of previous crayon drawings.

He fills the form in the website, and sends. He's asked to make a signature to prove that's him and that he's a human, and he publishes the offer for everyone to see.

### Technical details

When he "sends" the form, the frontend generates a JSON file.

```json
{
  "title": "Amazing Crayon Drawings",
  "description": "I will draw crayon drawings that will blow your mind",
  "terms": "https://ipfs.kleros.io/ipfs/Qmb9Mz1H5xPh9Mz8cVSAQzFJvCq2mXojjUJQFdiQpY1ak3/document.pdf",
  "price": "100000000000000000000000000000000000000",
  "token": "0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d",
  "timeForService": 604800,
  "timeForClaim": 259200,
  "sellerExtraUBIFee": 400,
  "pictures": [
    "https://ipfs.kleros.io/ipfs/Qmb9Mz1H5xPh9Mz8cVSAQzFJvCq2mXojjUJQFdiQpY1ak3/super_picture.png",
    "https://ipfs.kleros.io/ipfs/Qmb9Mz1H5xPh9Mz8cVSAQzFJvCq2mXojjUJQFdiQpY1ak3/super_picture2.png",
    "https://ipfs.kleros.io/ipfs/Qmb9Mz1H5xPh9Mz8cVSAQzFJvCq2mXojjUJQFdiQpY1ak3/super_picture3.png"
  ]
}
```

Let's look at what this means:

- Title: Self explanatory
- Description: Self explanatory
- Terms: An (optional?) document (in any format) explaining terms and conditions on how the deal will take place. If this doesn't exist, then the jurors will be forced to use common sense to arbitrate.
- Price: Amount the buyer needs to pay, at the very least. This huge number, without the 18 decimals, is "100".
- Token: The contract address of the Gnosis Chain ERC20 token. The frontend will query it and learn what it is.
- Time For Service: How much time the seller has to provide the service, in seconds.
- Time For Claim: How much time the buyer has to create a claim after the service is over, in seconds.
- Extra UBI Fee: How much the seller will donate to the UBI burner, in basis points. In this example, this is equivalent to 4%.
- Pictures: An array of image links. They don't need to be available in IPFS (although it's preferred), but they should be accessible.

> Keeping the token amount with the real decimals just makes it easier for your frontend to generate the proper parameters later. Plus, it's just more correct.

The frontend generates this file, and then asks Bob to sign this JSON file. No smart contract calls yet.

> Feel free to cut this part out from the first version, if you don't want to bother with verifying signatures. If you don't do it, at some point someone is going to flood the website, though. Also, even if you don't sign it, you will still need to generate this JSON file and store it somewhere along the offer.

## Alice Buys a Service

### What Alice sees

Alice gets in the website and spots a succulent offer for *crayon drawings*. She clicks on it, and wants to buy a drawing.

She connects with her PoH account. She wants to burn 10% of the price for UBI. She types in a specification for her order, and clicks on "Proceed to Buy". She signs an approval of 110 WXDAI. Then, she signs a contract interaction to create the deal.

### Technical details

Yubiai should refuse her to do this if she's not connected with her PoH account, although the contract is not able to stop her from creating the deal without being a human.

If she didn't have enough WXDAI in her account, the frontend would have told her she didn't have enough.
If she had had enough WXDAI approval to Yubiai contract, the frontend would let her Buy without making an unneeded approval.

When she clicks the deal, the following happens. Her specification is added as a new field on the JSON that Bob signed before. Her extra fee is also added in basis points (as `buyerExtraUBIFee`). Then, the frontend **uploads the JSON to IPFS**. Then, based on the URI returned by IPFS, the following string is generated:

`ipfs/Qmb9Mz1H5xPh9Mz8cVSAQzFJvCq2mXojjUJQFdiQpY1ak3/terms.json`

This string is required to construct the deal. The other parameters from the `Deal` struct are generated. In the end, the following `Deal` struct is created:

```
buyer: 0x411CE00000123456789012345678901234567890
state: 0
extraBurn: 1263
claimCount: 0
seller: 0xB0B0000000123456789012345678901234567890
token: 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d
amount: 110000000000000000000000000000000000000
createdAt: 0
timeForService: 604800
timeForClaim: 259200
currentClaim: 0
```

The following fields will be properly set by the contract, so they don't matter:
- state
- claimCount
- currentClaim
- createdAt

Let's explain the `extraBurnFee` parameter. The rate of extra UBI burn Alice sets is 10%. This rate is calculated from the offering price of 100 WXDAI, so, she's to burn 10 WXDAI.

Bob was burning an extra 4%. Adding this to the mandatory 1%, Bob will suffer a 5% fee from his brute income. So, he burns 5 WXDAI.
95 (net income) + 5 (seller fee) + 10 (buyer donation) = **110 WXDAI**. So far, so good.

In order to make it work, the tx Alice signs will imply there are 110 WXDAI as the buying price.
But, if you 

So, TLDR:

```javascript
// fees here are unitary ratios. e.g. 0.01
const contractAmount = originalOffering * (1 + buyerExtraFee) 
const netIncome = originalOffering * (1 - baseUBIFee - sellerExtraFee)
const extraBurnFee = netIncome / contractAmount - baseUBIFee
// this is the value you put on the contract
const basisPointsExtraBurn = Math.trunc(extraBurnFee * 10000) 
```

Remember that in the contract you will put 110 WXDAI instead of 100 WXDAI as well.

The transaction will also include the parameter `_terms`, which is equal to the IPFS string above. Making this work with IPFS is necessary here.

Alice signs the `createDeal(..., ...)` transaction and the deal is made.

When the transaction is mined, the event `DealCreated` is emitted, that holds the deal information and the terms.

## Alice is happy with the drawing

### What Alice Sees

3 days after, Bob sends the drawing to her privately. Alice loves it, and forwards the payment. She goes to Yubiai, clicks on her deal, and clicks on "Pay Service". She signs a transaction, and the deal is closed.

## Technical details

Alice goes to her deal. The frontend searches for `DealCreated`, `ClaimMade`, `ClaimClosed` and `DealClosed` events, with `dealId = 0`. It has ID 0 because this was the first deal in Yubiai.

The frontend figures out that the deal exists, and it wasn't closed. Now, it checks the status of the deal. It has status `Ongoing` (which equals `1`), so it knows the deal is ongoing and is not currently claimed.

Then, the frontend figures out that the connected wallet is the buyer, so it allows Alice to forward the payment if she so wishes.

As she clicks on "Pay Service", she's requested so sign `closeDeal(...)`. After it's mined, a `DealClosed` event will be emitted.

## Alice is not happy with the drawing

### What Alice Sees

In this world, Alice didn't like the payment. She complains to Bob, but he won't make an extra drawing. So, another 4 days pass, and now Alice is in the period for making claims. She makes a claim demanding 50 WXDAI back. She writes a very angry comment on why she's entitled to that amount. She signs a transaction, and makes a deposit of 15 xDAI, ready for creating a dispute if needed.

### Technical details

Alice goes to her deal. When the claiming period hadn't started, she wasn't able to click on the "Make Claim" button. The frontend knows she's not in the claiming period because it reads the `DealCreated` event, that holds the information needed to figure this. She waits the required amount of time.

4 days pass, she comes back. She can now make a claim. She types in 50 WXDAI of requested refund. Then she types in the reason behind this demand, and attaches an extra document with evidence, if needed.

When she does this, this demand is parsed into a JSON file, that will be treated as evidence, using the [EIP-1497 Evidence Standard](https://github.com/ethereum/EIPs/issues/1497). This is an example of such a JSON file.

```json
{
  "name": "The Drawing Sucks!",
  "description": "There is no way I'm paying 100$ for this crap, I want 50$ back. Reason attached.",
  "fileURI": "/ipfs/QmX9Py27H4kykMGaKz5kfzdPCbvC5ZSoDSh4rTq8SScPip/why-this-drawing-sucks.pdf",
  "fileTypeExtension": "pdf"
}
```

So, if she attached a file, the file is uploaded to IPFS first, then included onto this JSON, then this JSON is also uploaded (for example, labelled `evidence.json`). And the final IPFS URI returned will be used as a parameter of the function she's about to sign.

So, the frontend converts the "50 WXDAI" to the real amount in units, and gets Alice to sign the transaction `makeClaim`. In this transaction, she will need to also send 15 xDAI in `msg.value`, because that's the number that returns after you call the view function `arbitrationCost(...)` (if she doesn't have enough xDAI, the frontend should tell her). After this transaction is included into a block, the event `ClaimMade` is emitted.

## Bob Accepts the Claim

### What Bob Sees

Bob is notified of the claim. He gasps but ends up accepting and paying Alice her demanded 50 WXDAI. After all, the crayon drawing is worthless anyway. He goes to the frontend, and clicks "Refund 50 WXDAI". He signs the transaction, and pays Alice, while receiving some payment from the service.

### Technical details

The frontend reads the events, and notices that a `ClaimMade` was emitted, but a `ClaimClosed` wasn't emitted for that `claimId`. So, it knows that the deal is currently claimed. It shows regular deal data, and an additional window below with some claim data.

> Despite a Claim not being closed, it may happen that Bob simply never challenged the claim. In that case, just show all users a button to force the claim. For UX, you want a bot that automatically closes old deals and claims.

When Bob clicks on "Refund 50 WXDAI", a request to sign `acceptClaim(...)` is made to Bob. As the transaction is mined, Alice gets refunded, the deal is closed with the remainder that is used for fees and paying Bob.`ClaimClosed` and `DealClosed` are emitted.

## Bob Challenges the Claim

### What Bob Sees

Bob clicks on his deal, and sees Alice's claim. He sees the requested refund, and the reasoning.

"How dares she?" Bob thinks. So, he challenges Alice's claim. He has to deposit 15 xDAI, and then a dispute is created in Kleros.

### Technical details

Same deal as before, but Bob clicks "Challenge Claim" instead. The button won't be clickable if Bob doesn't have at least 15 xDAI to put as deposit. He signs `challengeClaim(...)`.

## Handling the Dispute

Don't worry about this, the contract uses IDisputeResolver, so, as far as I know, it can work seamlessly using Dispute Resolver. Just, if there's a Claim that has been disputed, show a link to the users to direct them to Dispute Resolver, so that they come there and can do all Kleros interactions in there.

In order to find the Kleros dispute, look for the `Dispute` event with `_evidenceGroupID` equal to `claimId`. Then, the `_disputeID` of that event will be the number of the Kleros dispute you're looking for. 

## Other Details

### Tracking UBI burns

In the future, it would be cool to see how much UBI an user burned (or, how much USD value they sent to the UBI burner). Also, show how much UBI a deal burned. If it's Ongoing, how much it could possibly burn.