//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;


import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin,DSCEngine,HelperConfig){
        HelperConfig config = new HelperConfig();
        ( address wethUsdPriceFeed,
        address wbtcUsdPriceFeed,
        address weth,
        address wbtc,
        uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth,wbtc];
        priceFeedAddresses = [wethUsdPriceFeed,wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin decentralizedStableCoin = new DecentralizedStableCoin();
        DSCEngine dSCEngine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(decentralizedStableCoin));
        decentralizedStableCoin.transferOwnership(address(dSCEngine));
        vm.stopBroadcast();

        return (decentralizedStableCoin,dSCEngine,config);
    }
}