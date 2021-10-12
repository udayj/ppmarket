This is a basic protocol for creating private lossless prediction markets on the blockchain. [Currently deployed on the kovan testnet].

2 parties can enter a bet and stake equal amounts with the smart contract. The protocol then deposits the total staked amount with Compound in return for cTokens. After the result of the bet (in this case price of ETH in USD) is known, the cTokens are redeemed from Compound. The original staked amounts are returned to the 2 parties and the winner additionally gets the interest earned as the prize.


initiateDeal(uint256 _val, uint _upOrDown, uint _timer) - this function is the starting point for creating a new bet/deal. Lets say person 'A' calls it with 3580,1,60. This means that A is betting that price of ETH will be more than $3580 after 60 seconds from when the 2nd part joins the deal. This function returns the dealId.

joinDeal(uint _dealId) - B now wants to join the bet using the dealId given by A. To do this B calls this function with the dealId.

After this, the protocol automatically does the rest, from depositing funds in Compound, to setting up an alarm after '_timer' seconds of delay, to checking the price feed from an oracle, to redeeming the cTokens that had been minted, to distributing the staked amounts and the prize.
