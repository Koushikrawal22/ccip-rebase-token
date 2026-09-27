# Cross-Chain Rebase Token

1.A protocol that allows users to deposit into vault and in return , receive rebase tokens that represent their underlying balance .
2. We will also create Rebase token  -> balanceOf function is dynamic to show the increasing balance with time 
  - Balance increases lineraly with time  
  - mint tokens to our user whenever they perfom an action (minting , burning, transferring , or...bridging)
3. Interest Rate 
  - Individually set an interest rate for each user based on some global interest rate of the protocol at the time users deposit into the vault.
  - This global interest rate can only decrease to reward/incentivise early adopters.
     -> Suppose  initially a protocol has a 10% of interest rate .
     -> After that it keeps rule that daily reduce global interest  rate slowly .
     -> So in this when a user deposits early that user can earn more/high interest rate than who are joining later . 
     Notice : when a user joins at that time current  global interest rate is set to that user and that fixed rate  will be fixed to that user .