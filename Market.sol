//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface CEth {
    function mint() external payable;
    function exchangeRateCurrent() external returns (uint256);
    function supplyRatePerBlock() external returns (uint256);
    function redeem(uint) external returns (uint);
    function redeemUnderlying(uint) external returns(uint);
    function balanceOf(address) external view returns(uint256);
    function balanceOfUnderlying(address) external returns(uint);

}


contract Market is ChainlinkClient, Ownable{
    
    using Chainlink for Chainlink.Request;
    event NewDeal(uint dealId, address initiator, uint256 val, uint upOrDown, uint timer);
    event DealJoined(uint dealId, address joiner);
    event DealCompleted(uint dealId, address winner);
    address payable _cEtherContract=payable(0x41B5844f4680a8C38fBb695b7F9CFd1F64474a72);
    address public oracle_alarm=0xF405B99ACa8578B9eb989ee2b69D518aaDb90c1F;
    bytes32 public jobId_alarm="a13ad0518c9d4ffdbdbd5bf745aefe02";
    address public oracle_price=0xc57B33452b4F7BB189bB5AfaE9cc4aBa1f7a4FD8;
    bytes32 public jobId_price="d5270d1c311941d0b08bead21fea7747";
    uint256 private fee=0.1*10**18;
   
    
    struct Deal {
        address payable initiator;
        address payable joiner;
        uint256 dealAmount;
        uint256 tokens;
        address payable winner;
        uint upOrDown;
        uint256 val;
        uint timer;
        uint256 currentTokens;
        uint256 ethRedeemed;
        uint state;
        uint256 result;
    }
    
    constructor () {
        setPublicChainlinkToken();
    }
    function setOracleAlarm(address _add) public  onlyOwner() {
        oracle_alarm=_add;
    }
    
    function setJobIdAlarm(bytes32 _job) public onlyOwner() {
        jobId_alarm=_job;    
    }
    
    function setOraclePrice(address _add) public onlyOwner() {
        oracle_price=_add;
    }
    function setJobIdPrice(bytes32 _job) public onlyOwner() {
        jobId_price=_job;
    }
    
    mapping (bytes32 => uint) requestIdTimerToDealId;
    mapping (bytes32 => uint) requestIdPriceToDealId;
    Deal[] public deals;
    
    function getDealAmount(uint _dealId) public view returns(uint256) {
        return deals[_dealId].dealAmount;
    }
    
    function getDealInitiator(uint _dealId) public view returns(address) {
        return deals[_dealId].initiator;
    }
    function getDealJoiner(uint _dealId) public view returns(address) {
        return deals[_dealId].joiner;
    }
    /*
    @param _val - value for the bet, both parties will need to place bet for same amount
    @param _upOrDown - 1 indicates initiator is betting price will be >= _val, any other value means <
    @param _timer - number of seconds to wait after deal is joined to verify result of bet
    @return dealId - to be used by joiner to join this bet
    */
    function initiateDeal(uint256 _val, uint _upOrDown, uint _timer) external payable returns(uint256) {
        
        require(msg.value>0,"Need to stake non-zero deal amount");
        deals.push(Deal(payable(msg.sender),payable(0), msg.value, 0,payable(0),_upOrDown,_val,_timer,0,0,0,0));
        uint dealId=deals.length-1;
        emit NewDeal(dealId, msg.sender, _val, _upOrDown,_timer);
        
        return dealId;
        
    }
    
    function getDealTokens(uint _dealId) public view returns(uint256) {
        return deals[_dealId].tokens;
    }
    
    function getDealWinner(uint _dealId) public view returns(address) {
        
        return deals[_dealId].winner;
    }
    
    function getDealCurrentTokens(uint _dealId) public view returns(uint256) {
        return deals[_dealId].currentTokens;
    }
    
    function getEthRedeemed(uint _dealId) public view returns(uint256) {
        return deals[_dealId].ethRedeemed;
    }
    
    function getDealState(uint _dealId) public view returns(uint) {
        return deals[_dealId].state;
    }
    
    function getDealResult(uint _dealId) public view returns(uint256) {
        return deals[_dealId].result;
    }
    /*
    @param _dealId - deal id generated when initiating address creates the bet
    @returns true if all goes well
    @dev - this function closes the bet when both parties stake same amount, deposits the staked amount to compound, calls delay
    */
    
    function joinDeal(uint _dealId) external payable returns(bool) {
        
        
        Deal storage deal=deals[_dealId];
        require(msg.value==deal.dealAmount,"Need to stake equal deal amount");
        require(deal.state==0,"Deal already closed");
        
        deal.joiner=payable(msg.sender);
        deal.state=1;
        supplyEthToCompound(_dealId,msg.value);
        delayCaller(deal.timer,_dealId);
        emit DealJoined(_dealId,msg.sender);
        return true;
    }
    /*
    @dev - this function adds the required delay before checking the result of bet at a future time
    chainlink alarm job is triggered based on required delay
    */
    function delayCaller(uint _timer,uint _dealId) internal {
        
        Chainlink.Request memory request = buildChainlinkRequest(jobId_alarm,address(this), this.fulfillDelay.selector);
        request.addUint("until",block.timestamp + _timer);
        bytes32 requestId=sendChainlinkRequestTo(oracle_alarm, request, fee);
        requestIdTimerToDealId[requestId]=_dealId;
        deals[_dealId].state=3;
        
    }
    
    /*
    @dev - this function actually triggers the call to requestPriceData to check the result of the bet
    its a public callback function which the chainlink oracle calls after required time delay
    */
    function fulfillDelay(bytes32 _requestId) public recordChainlinkFulfillment(_requestId){
        
     
        deals[requestIdTimerToDealId[_requestId]].state=4;
        requestPriceData(requestIdTimerToDealId[_requestId]);
    }
    
    /*
    @dev - this function triggers a call to the chainlink oracle for eth/usd price feed
    */
    function requestPriceData(uint _dealId) internal {
        Chainlink.Request memory request = buildChainlinkRequest(jobId_price, address(this), this.fulfill.selector);
        request.add("get", "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD");
        request.add("path","RAW.ETH.USD.PRICE");
        int timesAmount = 10**18;
        request.addInt("times", timesAmount);
        
        bytes32 requestId = sendChainlinkRequestTo(oracle_price, request, fee);
        requestIdPriceToDealId[requestId]=_dealId;
        deals[_dealId].state=5;
    }
    
    /*
    @dev - this function is called by the chainlink pricefeed oracle with the result of the bet - price of ETH in USD
    it checks the result, updates the deal based on dealId, and then distributes original staking amount to loser and balance to winner
    the balance amount will be original staking amount + the interest earned on compound (this interest is the prize)
    */
    function fulfill(bytes32 _requestId, uint256 _result) public recordChainlinkFulfillment(_requestId) {
        
        uint dealId=requestIdPriceToDealId[_requestId];
        Deal storage deal=deals[dealId];
        deal.result=_result;
        if(deal.upOrDown==1) {
            if(_result >= deal.val*(10**18)) {
                deal.winner=deal.initiator;
            }
            else {
                deal.winner=deal.joiner;
            }
            
        }
        else {
             if(_result < deal.val*(10**18)) {
                deal.winner=deal.initiator;
            }
            else {
                deal.winner=deal.joiner;
            }
        }
        
        deal.ethRedeemed=redeemCEth(deal.tokens);
        
        deal.currentTokens=0;
     
        if(deal.winner == deal.initiator) {
            (bool sent,)=(deal.joiner).call{value:deal.dealAmount}("");
            (sent,)=deal.initiator.call{value:deal.ethRedeemed-deal.dealAmount}("");
        }
        else {
            (bool sent,)=deal.initiator.call{value:deal.dealAmount}("");
            (sent,)=deal.joiner.call{value:deal.ethRedeemed-deal.dealAmount}("");   
        }
        deal.state=6;
        emit DealCompleted(dealId,deal.winner);
    }
    /*
    @param _dealId - the deal id
    @param _dealValue - the deal value for each participant in the bet
    @dev - this function deposits the staked amount on compouhnd and keeps track of the tokens earned in the deal struct
    when the bet result is out, these number tokens only will be redeemed
    */
    
    function supplyEthToCompound(uint _dealId, uint256 _dealValue) public returns(bool) {
        CEth cToken = CEth(_cEtherContract);
        uint256 tokensBefore=cToken.balanceOf(address(this));
        cToken.mint{value:_dealValue*2,gas:250000}();
        uint256 tokensAfter=cToken.balanceOf(address(this));
        Deal storage deal=deals[_dealId];
        deal.tokens=tokensAfter-tokensBefore;
        deal.currentTokens=tokensAfter-tokensBefore;
        deal.state=2;
        return true;
    }

    /*
    @param amount - number of tokens to redeem
    @dev this function redeems the number of tokens held with the bet, and returns the number of ETH redeemed (which should be more than what was deposited)
    */
    function redeemCEth (uint amount) public returns(uint) {

        CEth cToken=CEth(_cEtherContract);
        uint ethBefore=cToken.balanceOfUnderlying(address(this));
        uint redeemResult = cToken.redeem(amount);
        if(redeemResult ==0 ){}
        uint ethAfter=cToken.balanceOfUnderlying(address(this));
        return ethBefore-ethAfter;
    }
    
    fallback() external payable {}

    receive() external payable{}
    
     
    
    function getChainlinkTokenAddress() public view returns (address) {
        return chainlinkTokenAddress();
    }
    
    function setChainlinkTokenAddress(address _add) public onlyOwner() {
        setChainlinkToken(_add);
    }
    
}
