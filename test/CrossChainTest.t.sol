   // SPDX-License-Identifier: MIT
   pragma solidity ^0.8.18;

   import {Test, console} from "forge-std/Test.sol";
   import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
   import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
   import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
   import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
   import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
   import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
   import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
   import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

   import {RebaseToken} from "../src/RebaseToken.sol";
   import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
   import {Vault} from "../src/Vault.sol";

   import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

   contract CrossChaintest is Test {
      address owner = makeAddr("owner");
      address user = makeAddr("user");
      uint256 SEND_VALUE = 1e5;

      uint256 sepoliaFork;
      uint256 optSepoliaFork;
      CCIPLocalSimulatorFork ccipLocalSimulatorFork;

      RebaseToken sepoliaToken;
      RebaseToken optSepoliaToken;

      Vault sepoliaVault;

      RebaseTokenPool sepoliaPool;
      RebaseTokenPool optSepoliaPool;

      Register.NetworkDetails sepoliaNetworkDetails;
      Register.NetworkDetails optSepoliaNetworkDetails;

      function setUp() public {
         sepoliaFork = vm.createSelectFork("sepolia");
         optSepoliaFork = vm.createFork("opt-sepolia"); 
         ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
         vm.makePersistent(address(ccipLocalSimulatorFork));

         // Deploy and configure on Sepolia
         sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
         vm.startPrank(owner);
         sepoliaToken = new RebaseToken();
         sepoliaVault = new Vault(IRebaseToken(address(sepoliaToken)));
         sepoliaPool = new RebaseTokenPool(IERC20(address(sepoliaToken)),new address[](0),sepoliaNetworkDetails.rmnProxyAddress, sepoliaNetworkDetails.routerAddress );
         sepoliaToken.grantMintAndBurnRole(address(sepoliaVault));
         sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
         RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(sepoliaToken));
         TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
         TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(address(sepoliaToken) , address(sepoliaPool));
         vm.stopPrank();

         // Deploy and configure on Optimism-Sepolia
         vm.selectFork(optSepoliaFork);
         optSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
         vm.startPrank(owner);
         optSepoliaToken = new RebaseToken();    
         optSepoliaPool = new RebaseTokenPool(IERC20(address(optSepoliaToken)),new address[](0), optSepoliaNetworkDetails.rmnProxyAddress, optSepoliaNetworkDetails.routerAddress);
         optSepoliaToken.grantMintAndBurnRole(address(optSepoliaPool));
         RegistryModuleOwnerCustom(optSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(optSepoliaToken));
         TokenAdminRegistry(optSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(optSepoliaToken));
         TokenAdminRegistry(optSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(address(optSepoliaToken), address(optSepoliaPool));
         vm.stopPrank();
         configureTokenPool(sepoliaFork , address(sepoliaPool), optSepoliaNetworkDetails.chainSelector , address(optSepoliaPool) , address(optSepoliaToken));
         configureTokenPool(optSepoliaFork , address(optSepoliaPool), sepoliaNetworkDetails.chainSelector , address(sepoliaPool) , address(sepoliaToken));
      }

      function configureTokenPool(uint256 fork , address localPool , uint64 remoteChainSelector , address remotePoolAddress, address remoteTokenAddress ) public {
         vm.selectFork(fork);
         vm.startPrank(owner);
         bytes[] memory remotePoolAddresses = new bytes[](1);
         remotePoolAddresses[0] = abi.encode(remotePoolAddress); 
         
         TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
      
         chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector : remoteChainSelector,
            remotePoolAddresses :remotePoolAddresses,
            remoteTokenAddress : abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig : RateLimiter.Config({
               isEnabled : false,
               capacity : 0,
               rate : 0
            }),
            inboundRateLimiterConfig : RateLimiter.Config({
               isEnabled : false,
               capacity : 0,
               rate : 0
            })
         });
         TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
         vm.stopPrank();
      }

      function bridgeTokens(uint256 amountToBridge , uint256 localFork , uint256 remoteFork , Register.NetworkDetails memory localNetworkDetails , Register.NetworkDetails memory remoteNetworkDetails , RebaseToken localToken , RebaseToken remoteToken) public {
            vm.selectFork(localFork);
            vm.startPrank(user);
            Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
               token : address(localToken),
               amount : amountToBridge
            });
            Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
               receiver : abi.encode(user),
               data : "",
               tokenAmounts : tokenAmounts,
               feeToken : localNetworkDetails.linkAddress,
               extraArgs : Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit : 0}))
            });

            vm.stopPrank();
         uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector , message);
         ccipLocalSimulatorFork.requestLinkFromFaucet(user , fee);
         vm.startPrank(user);
         IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress , fee);
         IERC20(address(localToken)).approve(localNetworkDetails.routerAddress , amountToBridge);
         uint256 localBalanceBefore = localToken.balanceOf(user);
         console.logBytes(message.extraArgs);
         IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector , message);
         uint256 localBalanceAfter =  localToken.balanceOf(user);
         assertEq(localBalanceAfter , localBalanceBefore - amountToBridge);
         uint256 localInterestRate = localToken.getUserInterestRate(user);
         assertEq(localInterestRate , 5e10);
         vm.stopPrank();

         vm.selectFork(remoteFork);
         vm.warp(block.timestamp + 30 minutes);
         uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
         console.log("BEFORE ROUTING");
         console.log("Active fork:", vm.activeFork());
         ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
         console.log("AFTER ROUTING");
         console.log("Active fork:", vm.activeFork());
         console.log(
         "Destination balance:",
            remoteToken.balanceOf(user)
            );
         uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
         // assertEq(remoteBalanceAfter , remoteBalanceBefore + amountToBridge);
         // uint256 remoteInterestRate = remoteToken.getUserInterestRate(user);
         // assertEq(remoteInterestRate , localInterestRate);
         
      }  


      function testBridgeAllTokens() public {
         vm.selectFork(sepoliaFork);
         vm.deal(user , SEND_VALUE);
         vm.prank(user);
         Vault(payable(address(sepoliaVault))).deposit{value: SEND_VALUE}();
         assertEq(sepoliaToken.balanceOf(user) , SEND_VALUE);
         bridgeTokens(SEND_VALUE , sepoliaFork , optSepoliaFork , sepoliaNetworkDetails , optSepoliaNetworkDetails , sepoliaToken , optSepoliaToken);

         // vm.selectFork(optSepoliaFork);
         // vm.warp(block.timestamp + 20 minutes);
         // bridgeTokens(optSepoliaToken.balanceOf(user) , optSepoliaFork , sepoliaFork , optSepoliaNetworkDetails , sepoliaNetworkDetails , optSepoliaToken ,sepoliaToken );
      }
   }


