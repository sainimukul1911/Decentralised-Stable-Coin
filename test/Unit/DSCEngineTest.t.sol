//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;


import {console,Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address wethUSDPriceFeed;
    address weth;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (wethUSDPriceFeed,,weth,,) = config.activeNetworkConfig();
    }

    function testGetUSDValue() public {
        uint256 price = dsce.getUSDValue(wethUSDPriceFeed, 5000);
        assertEq(price, 10000000);
    }
}