// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokens is Script {
    function run(
        uint64 destinationChainSelector,
        address localRouterAddress,
        address receiver,
        address localTokenAddress,
        uint256 amountToSend,
        address linkTokenAddress
    ) public {
        vm.startBroadcast();
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: localTokenAddress, amount: amountToSend});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        uint256 ccipFee = IRouterClient(localRouterAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(localRouterAddress, ccipFee);
        IERC20(localTokenAddress).approve(localRouterAddress, amountToSend);
        IRouterClient(localRouterAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
