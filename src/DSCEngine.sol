//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Mukul Saini
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__AddressesArraysNotEqual();
    error DSCEngine__InvalidTokenAddress();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();


    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => uint256 amountMinted) private s_DscMinted;
    mapping(address user => mapping(address token => uint256 amount)) private s_collatoralDeposited;
    address[] private s_allPriceFeed;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    


    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token , uint256 indexed amount);


    modifier morethanzero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier validTokenAddress(address TokenAddress) {
        if (s_priceFeed[TokenAddress] == address(0)) {
            revert DSCEngine__InvalidTokenAddress();
        }
        _;
    }


    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__AddressesArraysNotEqual();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_allPriceFeed.push(priceFeedAddress[i]);
        }
        

        i_dsc = DecentralizedStableCoin(dscAddress);
    }


    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amount) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amount);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        morethanzero(amountCollateral)
        validTokenAddress(tokenCollateralAddress)
        nonReentrant
    {
        s_collatoralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender , tokenCollateralAddress , amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom( msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc(uint256 amount) external morethanzero(amount) nonReentrant{
        s_DscMinted[msg.sender] += amount;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender,amount);
        if(!minted){
            revert DSCEngine__MintingFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor(address user) external view {
        return _healthFactor(user);
    }


    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthfactor = _healthFactor(user);
        if(healthfactor<1){
            revert DSCEngine__BreaksHealthFactor(healthfactor);
        }
    }

    function _healthFactor(address user) private view returns(uint256){
        (uint256 mintedDSC,uint256 amountCollateral) = getUserInfo(user);
        uint256 collatoralAdjustedForThreshold = (amountCollateral * LIQUIDATION_THRESHOLD)/ LIQUIDATION_PRECISION; 
        return ((collatoralAdjustedForThreshold * PRECISION) /mintedDSC) ;
    }

    function getUserInfo(address user) internal view returns(uint256 mintedDSC, uint256 amountcollateral){
        uint256 amountCollateral;
        for(uint256 i=0;i<s_allPriceFeed.length;i++){
            amountCollateral += getUSDValue(s_allPriceFeed[i],s_collatoralDeposited[user][s_allPriceFeed[i]]);
        }
        return(s_DscMinted[user],amountCollateral);
    }

    function getUSDValue(address pricefeed,uint256 amount) public view returns (uint256){
        if(amount==0) {return 0;}
        AggregatorV3Interface priceFeed = AggregatorV3Interface(pricefeed);
        (,int256 pricee,,,) = priceFeed.latestRoundData();
        
        return ((uint256(pricee)*ADDITIONAL_FEED_PRECISION) * amount)/ PRECISION;
    }
}
