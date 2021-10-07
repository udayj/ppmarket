//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

interface CEth {
    function mint() external payable;
    function exchangeRateCurrent() external returns (uint256);
    function supplyRatePerBlock() external returns (uint256);
    function redeem(uint) external returns (uint);
    function redeemUnderlying(uint) external returns(uint);
    function balanceOf(address) external view returns(uint256);
    function balanceOfUnderlying(address) external returns(uint);

}

contract Market is ChainlinkClient {
    
    using Chainlink for Chainlink.Request;
    event NewDeal(uint, address, uint256, uint, uint);
    address payable _cEtherContract=payable(0x41B5844f4680a8C38fBb695b7F9CFd1F64474a72);
    address private oracle_alarm=0xF405B99ACa8578B9eb989ee2b69D518aaDb90c1F;
    bytes32 private jobId_alarm="a13ad0518c9d4ffdbdbd5bf745aefe02";
    address private oracle_price=0xc57B33452b4F7BB189bB5AfaE9cc4aBa1f7a4FD8;
    bytes32 private jobId_price="d5270d1c311941d0b08bead21fea7747";
    uint256 private fee=0.1*10**18;
    uint256 public counter;
    struct Deal {
        address payable initiator;
        address payable joiner;
        uint256 dealAmount;
        uint256 tokens;
        bool decided;
        address payable winner;
        uint upOrDown;
        uint256 val;
        uint timer;
        
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
    function initiateDeal(uint256 _val, uint _upOrDown, uint _timer) external payable returns(uint256) {
        
        
        deals.push(Deal(payable(msg.sender),payable(0), msg.value, 0,false,payable(0),_upOrDown,_val,_timer));
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
    function joinDeal(uint _dealId) external payable returns(bool) {
        
        Deal storage deal=deals[_dealId];
        deal.joiner=payable(msg.sender);
        //supplyEthToCompound(_dealId,msg.value);
        //delayCaller(deal.timer,_dealId);
        return true;
    }
    
    function delayCaller(uint _timer,uint _dealId) public {
        
        Chainlink.Request memory request = buildChainlinkRequest(jobId_alarm,address(this), this.fulfillDelay.selector);
        request.addUint("until",block.timestamp + (_timer * 60));
        bytes32 requestId=sendChainlinkRequestTo(oracle_alarm, request, fee);
        requestIdTimerToDealId[requestId]=_dealId;
        
    }
    
    function fulfillDelay(bytes32 _requestId) public recordChainlinkFulfillment(_requestId){
        
        counter++;
        
        requestPriceData(requestIdTimerToDealId[_requestId]);
    }
    
    function requestPriceData(uint _dealId) public {
        Chainlink.Request memory request = buildChainlinkRequest(jobId_price, address(this), this.fulfill.selector);
        request.add("get", "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD");
        request.add("path","RAW.ETH.USD.PRICE");
        int timesAmount = 10**18;
        request.addInt("times", timesAmount);
        
        bytes32 requestId = sendChainlinkRequestTo(oracle_price, request, fee);
        requestIdPriceToDealId[requestId]=_dealId;
    }
    
    function fulfill(bytes32 _requestId, uint256 _result) public recordChainlinkFulfillment(_requestId) {
        
        uint dealId=requestIdPriceToDealId[_requestId];
        Deal storage deal=deals[dealId];
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
        
        uint ethRedeemed=redeemCEth(deal.tokens);
        deal.decided=true;
        if(deal.winner == deal.initiator) {
            (bool sent,)=(deal.joiner).call{value:deal.dealAmount}("");
            (sent,)=deal.initiator.call{value:ethRedeemed-deal.dealAmount}("");
        }
        else {
            (bool sent,)=deal.initiator.call{value:deal.dealAmount}("");
            (sent,)=deal.joiner.call{value:ethRedeemed-deal.dealAmount}("");   
        }
    }
    
    function supplyEthToCompound(uint _dealId, uint256 _dealValue) public returns(bool) {
        CEth cToken = CEth(_cEtherContract);
        uint256 tokensBefore=cToken.balanceOf(address(this));
        cToken.mint{value:_dealValue*2,gas:250000}();
        uint256 tokensAfter=cToken.balanceOf(address(this));
        Deal storage deal=deals[_dealId];
        deal.tokens=tokensAfter-tokensBefore;
        return true;
    }

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
    
}
