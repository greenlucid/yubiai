// SPDX-License-Identifier: Unlicensed

/**
 *  @authors: [@greenlucid]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity ^0.8.16;

import "@kleros/erc-792/contracts/IArbitrable.sol";
import "@kleros/erc-792/contracts/IArbitrator.sol";
import "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@kleros/dispute-resolver-interface-contract/contracts/IDisputeResolver.sol";

contract Yubiai is IDisputeResolver {
  // None: It hasn't even begun.
  // Ongoing: Exists, it's not currently being claimed.
  // Claimed: The seller made a claim to obtain a refund.
  // Finished: It's over.
  enum DealState {None, Ongoing, Claimed, Disputed, Finished}

  enum ClaimResult {Rejected, Accepted}

  // Round struct stores the contributions made to particular rulings.
  struct Round {
    mapping(uint256 => uint256) paidFees; // Tracks the fees paid in this round in the form paidFees[ruling].
    mapping(uint256 => bool) hasPaid; // True if the fees for this particular answer have been fully paid in the form hasPaid[ruling].
    mapping(address => mapping(uint256 => uint256)) contributions; // Maps contributors to their contributions for each ruling in the form contributions[address][answer].
    uint256 feeRewards; // Sum of reimbursable appeal fees available to the parties that made contributions to the ruling that ultimately wins a dispute.
    uint256[] fundedAnswers; // Stores the choices that are fully funded.
  }

  struct Claim {
    uint256 dealId;
    uint256 disputeId;
    uint256 amount;
    uint256 createdAt;
    uint256 solvedAt; // if zero, unsolved yet.
    uint256 ruling;
    uint256 arbSettingsId;
    Round[] rounds;
  }

  struct Deal {
    address buyer;
    DealState state;
    uint32 extraBurnFee;
    uint32 claimCount;
    address seller;
    IERC20 token;
    uint256 amount;
    uint256 createdAt;
    uint256 timeForService;
    uint256 timeForClaim;
    uint256 currentClaim;
  }

  struct YubiaiSettings {
    address admin;
    uint32 maxClaims; // max n claims per deal. a deal is automatically closed if last claim fails.
    uint32 timeForReclaim; // time the buyer has to create new claim after losing prev
    uint32 timeForChallenge; // time the seller has to challenge a claim, and accepted otherwise.
    address ubiBurner;
    // fees are in basis points
    uint32 adminFee;
    uint32 ubiFee;
    uint32 maxExtraFee; // this must be at all times under 10000 to prevent drain attacks.
    // ---
    // enforce timespans for prevent attacks
    uint32 minTimeForService;
    uint32 maxTimeForService;
    uint32 minTimeForClaim;
    uint32 maxTimeForClaim;
  }

  event DealCreated(uint256 indexed dealId, Deal deal, string terms);
  event ClaimCreated(uint256 indexed dealId, uint256 indexed claimId, uint256 amount, string evidence);
  
  event ClaimClosed(uint256 indexed claimId, ClaimResult indexed result);

  event DealClosed(
    uint256 indexed dealId, uint256 payment, uint256 refund,
    uint256 ubiFee, uint256 adminFee
  );

  /// 0: Refuse to Arbitrate (Don't refund)
  /// 1: Don't refund
  /// 2: Refund
  uint256 constant NUMBER_OF_RULINGS = 2;

  uint256 constant BASIS_POINTS = 10_000;

  // hardcoded the multipliers for efficiency. they've been shown to work fine.
  uint256 constant WINNER_STAKE_MULTIPLIER = 5_000;
  uint256 constant LOSER_STAKE_MULTIPLIER = 10_000;
  uint256 constant LOSER_APPEAL_PERIOD_MULTIPLIER = 5_000;

  uint256 public dealCount;
  uint256 public claimCount;
  YubiaiSettings public settings;
  address public governor;

  mapping(uint256 => Deal) public deals;
  mapping(uint256 => Claim) public claims;

  IArbitrator public arbitrator;
  uint256 public currentArbSettingId;
  mapping(uint256 => uint256) public disputeIdToClaim;
  mapping(uint256 => bytes) public extraDatas;
  mapping(IERC20 => bool) public tokenValidity;

  /**
   * @dev Initializes the contract.
   * @param _settings Initial settings of Yubiai.
   * @param _governor Governor of Yubiai, can change settings.
   * @param _metaEvidence The immutable metaEvidence.
   */
  constructor(
    YubiaiSettings memory _settings,
    address _governor,
    IArbitrator _arbitrator,
    bytes memory _extraData,
    string memory _metaEvidence
  ) {
    settings = _settings;
    governor = _governor;
    arbitrator = _arbitrator;
    extraDatas[0] = _extraData;
    emit MetaEvidence(0, _metaEvidence);
  }

  /**
   * @dev Change settings of Yubiai, only governor.
   * @param _settings New settings.
   */
  function changeSettings(YubiaiSettings memory _settings) external {
    require(msg.sender == governor, "Only governor");
    settings = _settings;
  }

  /**
   * @dev Change governor of Yubiai, only governor.
   * @param _governor New governor.
   */
  function changeGovernor(address _governor) external {
    require(msg.sender == governor, "Only governor");
    governor = _governor;
  }

  /**
   * @dev Change arbSettings of Yubiai, only governor.
   * @param _extraData New arbitratorExtraData
   * @param _metaEvidence New MetaEvidence
   */
  function newArbSettings(bytes calldata _extraData, string calldata _metaEvidence) external {
    require(msg.sender == governor, "Only governor");
    currentArbSettingId++;
    extraDatas[currentArbSettingId] = _extraData;
    emit MetaEvidence(currentArbSettingId, _metaEvidence);
  }

  /**
   * @dev Toggle validity on an ERC20 token, only governor.
   * @param _token Token to change validity of.
   * @param _validity Whether if it's valid or not.
   */
  function setTokenValidity(IERC20 _token, bool _validity) external {
    require(msg.sender == governor, "Only governor");
    tokenValidity[_token] = _validity;
  }

  /**
   * @dev Creates a deal, an agreement between buyer and seller.
   * @param _deal The deal that is to be created. Some properties may be mutated.
   */
  function createDeal(Deal memory _deal, string memory _terms) public {
    require(
      _deal.token.transferFrom(msg.sender, address(this), _deal.amount),
      "Token transfer failed"
    );
    // offering received. that's all you need.
    _deal.createdAt = block.timestamp;
    _deal.state = DealState.Ongoing;
    _deal.claimCount = 0;
    _deal.currentClaim = 0;
    // additional validation could take place here:
    // verify max extra fee
    require(_deal.extraBurnFee <= settings.maxExtraFee, "Extra fee too large");
    // only allowed tokens
    require(tokenValidity[_deal.token], "Invalid token");
    // only allowed time spans
    require(_deal.timeForService >= settings.minTimeForService, "Too little time for service");
    require(_deal.timeForClaim >= settings.minTimeForClaim, "Too little time for claim");
    require(_deal.timeForService <= settings.maxTimeForService, "Too much time for service");
    require(_deal.timeForClaim <= settings.maxTimeForClaim, "Too much time for claim");
    
    deals[dealCount] = _deal;
    emit DealCreated(dealCount, _deal, _terms);
    dealCount++;
  }

  /**
   * @dev Closes a deal. Different actors can close the deal, depending on some conditions.
   * @param _dealId The ID of the deal to be closed.
   */
  function closeDeal(uint256 _dealId) public {
    Deal storage deal = deals[_dealId];
    require(deal.state == DealState.Ongoing, "Deal is not ongoing");
    // 1. if over the time for service + claim, anyone can close it.
    if (isOver(_dealId)) {
      _closeDeal(_dealId, deal.amount);
    } else {
      // 2. if under, the buyer can decide to pay the seller.
      require(deal.buyer == msg.sender, "Only buyer can forward payment");
      _closeDeal(_dealId, deal.amount);
    }
  }

  /**
    notes about claims and an edge case
    in order to make a claim, ideally, you want both parties to
    put skin in the game. the buyer needs to put the arb cost (value)
    and the seller can put it as well and launch a dispute.
    whoever wins that dispute retrieves their stake.
    however, arbitration fees could change after the buyer put their
    stake. an ugly "way" around it is, calculating the arb cost ad hoc,
    also for refunds. yubiai marketplace can subsidize the difference.
    arbitration fees shouldn't change often anyway.
  */

  /**
   * @dev Make a claim on an existing claim. Only the buyer can claim.
   * @param _dealId The ID of the deal to be closed.
   * @param _amount Amount to be refunded.
   * @param _evidence Rationale behind the requested refund.
   */
  function makeClaim(uint256 _dealId, uint256 _amount, string calldata _evidence) external payable {
    Deal storage deal = deals[_dealId];
    require(msg.sender == deal.buyer, "Only buyer");
    require(deal.amount >= _amount, "Refund cannot be greater than deal");
    require(deal.state == DealState.Ongoing && !isOver(_dealId), "Deal cannot be claimed");
    uint256 arbFees = arbitrator.arbitrationCost(extraDatas[currentArbSettingId]);
    require(msg.value >= arbFees, "Not enough to cover fees");
    Claim storage claim = claims[claimCount];
    claim.dealId = _dealId;
    claim.amount = _amount;
    claim.createdAt = block.timestamp;
    claim.arbSettingsId = currentArbSettingId;
    emit ClaimCreated(_dealId, claimCount, _amount, _evidence);
    claimCount++;
    deal.state = DealState.Claimed;
  }

  /**
   * @dev Accept the claim and pay the refund, only be seller.
   * @param _claimId The ID of the claim to accept.
   */
  function acceptClaim(uint256 _claimId) public {
    Claim storage claim = claims[_claimId];
    Deal storage deal = deals[claim.dealId];
    require(deal.state == DealState.Claimed, "Deal is not Claimed");
    if (block.timestamp >= claim.createdAt + settings.timeForChallenge) {
      // anyone can force a claim that went over the period
    } else {
      // only the seller can accept it
      require(deal.seller == msg.sender, "Only seller");
    }

    uint256 arbFees = arbitrator.arbitrationCost(extraDatas[claim.arbSettingsId]);
    _closeDeal(claim.dealId, deal.amount - claim.amount);
    claim.solvedAt = block.timestamp;
    deal.token.transfer(deal.buyer, claim.amount);
    emit ClaimClosed(_claimId, ClaimResult.Accepted);
    payable(deal.buyer).send(arbFees); // it is the buyer responsability to accept eth.
  }

  /**
   * @dev Challenge a refund claim, only by seller. A dispute will be created.
   * @param _claimId The ID of the claim to challenge.
   */
  function challengeClaim(uint256 _claimId) public payable {
    Claim storage claim = claims[_claimId];
    Deal storage deal = deals[claim.dealId];
    require(msg.sender == deal.seller, "Only seller");
    require(deal.state == DealState.Claimed, "Deal is not Claimed");
    require(block.timestamp < claim.createdAt + settings.timeForChallenge, "Too late for challenge");

    uint256 arbFees = arbitrator.arbitrationCost(extraDatas[claim.arbSettingsId]);
    require(msg.value >= arbFees, "Not enough to cover fees");

    // all good now.
    uint256 disputeId =
      arbitrator.createDispute{value: arbFees}(NUMBER_OF_RULINGS, extraDatas[claim.arbSettingsId]);
    disputeIdToClaim[disputeId] = _claimId;
    claim.disputeId = disputeId;

    deal.state = DealState.Disputed;
    
    emit Dispute(arbitrator, disputeId, claim.arbSettingsId, _claimId);
  }

  /**
   * @dev Rule on a claim, only by arbitrator.
   * @param _disputeId The external ID of the dispute.
   * @param _ruling The ruling. 0 and 1 will not refund, 2 will refund.
   */
  function rule(uint256 _disputeId, uint256 _ruling) external {
    require(msg.sender == address(arbitrator), "Only arbitrator rules");
    uint256 claimId = disputeIdToClaim[_disputeId];
    Claim storage claim = claims[claimId];
    Deal storage deal = deals[claim.dealId];
    require(deal.state == DealState.Disputed, "Deal is not Disputed");
    claim.solvedAt = block.timestamp;
    // get arb fees for refunds. if extraData was modified,
    // yubiai should send value to the contract to stop from halting.
    uint256 arbFees = arbitrator.arbitrationCost(extraDatas[claim.arbSettingsId]);
    deal.state = DealState.Ongoing; // will be overwritten if needed.
    // if 0 (RtA) or 1 (Don't refund)...
    if (_ruling < 2) {
      // was this the last claim? if so, close deal with everything
      if (deal.claimCount >= settings.maxClaims) {
        _closeDeal(claim.dealId, deal.amount);
      }
      payable(deal.seller).send(arbFees);
      emit ClaimClosed(claimId, ClaimResult.Rejected);
    } else {
      deal.token.transfer(deal.buyer, claim.amount);
      _closeDeal(claim.dealId, deal.amount - claim.amount);
      // refund buyer
      payable(deal.buyer).send(arbFees);
      emit ClaimClosed(claimId, ClaimResult.Accepted);
    }
    emit Ruling(arbitrator, _disputeId, _ruling);
  }

  /**
   * @dev Read whether if a claim is over or not.
   * @param _dealId Id of the deal to check.
   */
  function isOver(uint256 _dealId) public view returns (bool) {
    Deal memory deal = deals[_dealId];
    // if finished, then it's "over"
    if (deal.state == DealState.Finished) return (true);
    // if none, it hasn't even begun. if claimed or disputed, it can't be over yet.
    if (
      deal.state == DealState.None
      || deal.state == DealState.Claimed
      || deal.state == DealState.Disputed
    ) return (false);
    // so, it's Ongoing. if no claims, then createdAt is the reference
    if (deal.claimCount == 0) {
      return (block.timestamp >= (deal.createdAt + deal.timeForService + deal.timeForClaim));
    } else {
      // if was ever claimed, the date of the last claim being solved is the reference.
      return (block.timestamp >= (claims[deal.currentClaim].solvedAt + settings.timeForReclaim));
    }
  }

  /**
   * @dev Internal function to close the deal. It will process the fees
   * @param _dealId Id of the deal to check.
   */
  function _closeDeal(uint256 _dealId, uint256 _amount) internal {
    Deal storage deal = deals[_dealId];

    uint256 ubiFee = _amount * (settings.ubiFee + deal.extraBurnFee) / BASIS_POINTS;
    uint256 adminFee = _amount * settings.adminFee / BASIS_POINTS;

    uint256 toSeller = _amount - ubiFee - adminFee;

    deal.token.transfer(deal.seller, toSeller);
    deal.token.transfer(settings.admin, adminFee);
    deal.token.transfer(settings.ubiBurner, ubiFee);
    deal.state = DealState.Finished;

    emit DealClosed(_dealId, toSeller, deal.amount - _amount, ubiFee, adminFee);
  }

  // IDisputeResolver VIEWS

  /** @dev Maps external (arbitrator side) dispute id to local (arbitrable) dispute id.
    *  @param _externalDisputeID Dispute id as in arbitrator contract.
    *  @return localDisputeID Dispute id as in arbitrable contract.
    */
  function externalIDtoLocalID(uint256 _externalDisputeID) external view override returns (uint256 localDisputeID) {
    localDisputeID = disputeIdToClaim[_externalDisputeID];
  }

  /** @dev Returns number of possible ruling options. Valid rulings are [0, return value].
   *  @return count The number of ruling options.
   */
  function numberOfRulingOptions(uint256) external pure override returns (uint256 count) {
    count = NUMBER_OF_RULINGS;
  }

  /** @dev Allows to submit evidence for a given dispute.
   *  @param _claimId Identifier of a dispute in scope of arbitrable contract. Arbitrator ids can be translated to local ids via externalIDtoLocalID.
   *  @param _evidenceURI IPFS path to evidence, example: '/ipfs/Qmarwkf7C9RuzDEJNnarT3WZ7kem5bk8DZAzx78acJjMFH/evidence.json'
   */
  function submitEvidence(uint256 _claimId, string calldata _evidenceURI) external override {
    emit Evidence(arbitrator, _claimId, msg.sender, _evidenceURI);
  }

  /** @dev Returns appeal multipliers.
   *  @return winnerStakeMultiplier Winners stake multiplier.
   *  @return loserStakeMultiplier Losers stake multiplier.
   *  @return loserAppealPeriodMultiplier Losers appeal period multiplier. The loser is given less time to fund its appeal to defend against last minute appeal funding attacks.
   *  @return denominator Multiplier denominator in basis points.
   */
  function getMultipliers() external pure override returns (uint256, uint256, uint256, uint256) {
    return (
      WINNER_STAKE_MULTIPLIER,
      LOSER_STAKE_MULTIPLIER,
      LOSER_APPEAL_PERIOD_MULTIPLIER,
      BASIS_POINTS
    );
  }

  // IDisputeResolver APPEALS

  /** @dev Manages contributions and calls appeal function of the specified arbitrator to appeal a dispute. This function lets appeals be crowdfunded.
   *  @param _claimId Identifier of a dispute in scope of arbitrable contract. Arbitrator ids can be translated to local ids via externalIDtoLocalID.
   *  @param _ruling The ruling option to which the caller wants to contribute.
   *  @return fullyFunded True if the ruling option got fully funded as a result of this contribution.
   */
  function fundAppeal(uint256 _claimId, uint256 _ruling) external payable override returns (bool fullyFunded) {
    Claim storage claim = claims[_claimId];
    Deal storage deal = deals[claim.dealId];
    require(deal.state == DealState.Disputed, "No dispute to appeal.");

    uint256 disputeId = claim.disputeId;
    (uint256 appealPeriodStart, uint256 appealPeriodEnd) = arbitrator.appealPeriod(disputeId);
    require(block.timestamp >= appealPeriodStart && block.timestamp < appealPeriodEnd, "Appeal period is over.");

    uint256 multiplier;
    {
      uint256 winner = arbitrator.currentRuling(disputeId);
      if (winner == _ruling) {
        multiplier = WINNER_STAKE_MULTIPLIER;
      } else {
        require(
          block.timestamp - appealPeriodStart <
            (appealPeriodEnd - appealPeriodStart) * LOSER_APPEAL_PERIOD_MULTIPLIER / BASIS_POINTS,
          "Appeal period is over for loser"
        );
        multiplier = LOSER_STAKE_MULTIPLIER;
      }
    }

    uint256 lastRoundID = claim.rounds.length - 1;
    Round storage round = claim.rounds[lastRoundID];
    require(!round.hasPaid[_ruling], "Appeal fee is already paid.");
    uint256 appealCost = arbitrator.appealCost(disputeId, extraDatas[claim.arbSettingsId]);
    uint256 totalCost = appealCost + (appealCost * multiplier / BASIS_POINTS);

    // Take up to the amount necessary to fund the current round at the current costs.
    uint256 contribution = (totalCost - round.paidFees[_ruling]) > msg.value
        ? msg.value
        : totalCost - round.paidFees[_ruling];
    emit Contribution(_claimId, lastRoundID, _ruling, msg.sender, contribution);

    round.contributions[msg.sender][_ruling] += contribution;
    round.paidFees[_ruling] += contribution;
    if (round.paidFees[_ruling] >= totalCost) {
        round.feeRewards += round.paidFees[_ruling];
        round.fundedAnswers.push(_ruling);
        round.hasPaid[_ruling] = true;
        emit RulingFunded(_claimId, lastRoundID, _ruling);
    }

    if (round.fundedAnswers.length > 1) {
        // At least two sides are fully funded.
        claim.rounds.push();

        round.feeRewards = round.feeRewards - appealCost;
        arbitrator.appeal{value: appealCost}(disputeId, extraDatas[claim.arbSettingsId]);
    }

    if (contribution < msg.value) payable(msg.sender).send(msg.value - contribution); // Sending extra value back to contributor. It is the user's responsibility to accept ETH.
    return round.hasPaid[_ruling];
  }

  /**
   * @notice Sends the fee stake rewards and reimbursements proportional to the contributions made to the winner of a dispute. Reimburses contributions if there is no winner.
   * @param _claimId The ID of the claim.
   * @param _beneficiary The address to send reward to.
   * @param _round The round from which to withdraw.
   * @param _ruling The ruling to request the reward from.
   * @return reward The withdrawn amount.
   */
  function withdrawFeesAndRewards(
    uint256 _claimId,
    address payable _beneficiary,
    uint256 _round,
    uint256 _ruling
  ) public override returns (uint256 reward) {
    Claim storage claim = claims[_claimId];
    Round storage round = claim.rounds[_round];
    require(claim.solvedAt != 0, "Claim not resolved");
    // Allow to reimburse if funding of the round was unsuccessful.
    if (!round.hasPaid[_ruling]) {
      reward = round.contributions[_beneficiary][_ruling];
    } else if (!round.hasPaid[claim.ruling]) {
      // Reimburse unspent fees proportionally if the ultimate winner didn't pay appeal fees fully.
      // Note that if only one side is funded it will become a winner and this part of the condition won't be reached.
      reward = round.fundedAnswers.length > 1
          ? (round.contributions[_beneficiary][_ruling] * round.feeRewards) /
              (round.paidFees[round.fundedAnswers[0]] + round.paidFees[round.fundedAnswers[1]])
          : 0;
    } else if (claim.ruling == _ruling) {
      uint256 paidFees = round.paidFees[_ruling];
      // Reward the winner.
      reward = paidFees > 0 ? (round.contributions[_beneficiary][_ruling] * round.feeRewards) / paidFees : 0;
    }

    if (reward != 0) {
      round.contributions[_beneficiary][_ruling] = 0;
      _beneficiary.send(reward); // It is the user's responsibility to accept ETH.
      emit Withdrawal(_claimId, _round, _ruling, _beneficiary, reward);
    }
  }

  /**
   * @notice Allows to withdraw any rewards or reimbursable fees for all rounds at once.
   * @dev This function is O(n) where n is the total number of rounds. Arbitration cost of subsequent rounds is `A(n) = 2A(n-1) + 1`.
   *      So because of this exponential growth of costs, you can assume n is less than 10 at all times.
   * @param _claimId The ID of the arbitration.
   * @param _beneficiary The address that made contributions.
   * @param _contributedTo Answer that received contributions from contributor.
   */
  function withdrawFeesAndRewardsForAllRounds(
    uint256 _claimId,
    address payable _beneficiary,
    uint256 _contributedTo
  ) external override {
    uint256 numberOfRounds = claims[_claimId].rounds.length;
    
    for (uint256 roundNumber = 0; roundNumber < numberOfRounds; roundNumber++) {
      withdrawFeesAndRewards(_claimId, _beneficiary, roundNumber, _contributedTo);
    }
  }

  /**
   * @notice Returns the sum of withdrawable amount.
   * @dev This function is O(n) where n is the total number of rounds.
   * @dev This could exceed the gas limit, therefore this function should be used only as a utility and not be relied upon by other contracts.
   * @param _claimId The ID of the arbitration.
   * @param _beneficiary The contributor for which to query.
   * @param _contributedTo Answer that received contributions from contributor.
   * @return sum The total amount available to withdraw.
   */
  function getTotalWithdrawableAmount(
    uint256 _claimId,
    address payable _beneficiary,
    uint256 _contributedTo
  ) external view override returns (uint256 sum) {
    if (claims[_claimId].solvedAt == 0) return sum;

    uint256 finalAnswer = claims[_claimId].ruling;
    uint256 noOfRounds = claims[_claimId].rounds.length;
    for (uint256 roundNumber = 0; roundNumber < noOfRounds; roundNumber++) {
      Round storage round = claims[_claimId].rounds[roundNumber];

      if (!round.hasPaid[_contributedTo]) {
        // Allow to reimburse if funding was unsuccessful for this answer option.
        sum += round.contributions[_beneficiary][_contributedTo];
      } else if (!round.hasPaid[finalAnswer]) {
        // Reimburse unspent fees proportionally if the ultimate winner didn't pay appeal fees fully.
        // Note that if only one side is funded it will become a winner and this part of the condition won't be reached.
        sum += round.fundedAnswers.length > 1
          ? (round.contributions[_beneficiary][_contributedTo] * round.feeRewards) /
            (round.paidFees[round.fundedAnswers[0]] + round.paidFees[round.fundedAnswers[1]])
          : 0;
      } else if (finalAnswer == _contributedTo) {
        uint256 paidFees = round.paidFees[_contributedTo];
        // Reward the winner.
        sum += paidFees > 0
          ? (round.contributions[_beneficiary][_contributedTo] * round.feeRewards) / paidFees
          : 0;
      }
    }
  }
}
