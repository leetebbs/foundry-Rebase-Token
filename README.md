# crosschain rebase token
1. A protocol that allows user to deposit into a vault and inreturn , recieve a rebase tokens that represent their underlying balance
2. Rebase Token - balanceOf function is dynamic to show the changing balance with time.
-balance increases linierly with time.
- mint tokens to our users ervery time they perform an action (minting, burning, transfering , or ... bridging)
3. Interest rate 
 - Individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault.
 - This global interest rate can only decrease to incentivise/reward early adopters.
 - Increase token adoption