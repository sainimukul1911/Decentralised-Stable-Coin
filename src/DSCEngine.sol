//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();


    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => uint256 amountMinted) private s_DscMinted;
    mapping(address user => mapping(address token => uint256 amount)) private s_collatoralDeposited;
    address[] private s_allPriceFeed;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    


    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token , uint256 indexed amount);
    event CollateralRedeemed(address indexed fromUser, address indexed toUser, address indexed token , uint256 indexed amount);


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
        public
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

    function redeemCollateralForDsc(uint256 amountToRedeem, address tokenCollateralAddress, uint256 amounttoBurn) external morethanzero(amountToRedeem){
        burnDsc(amounttoBurn);
        redeemCollateral(amountToRedeem, tokenCollateralAddress);
    }

    function redeemCollateral(uint256 amount , address tokenCollateralAddress) public morethanzero(amount) nonReentrant{
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amount);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amount) public morethanzero(amount) nonReentrant{
        s_DscMinted[msg.sender] += amount;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender,amount);
        if(!minted){
            revert DSCEngine__MintingFailed();
        }
    }

    function burnDsc(uint256 amount) public morethanzero(amount) nonReentrant{
        _burnDSC(msg.sender, msg.sender, amount);
        i_dsc.burn(amount);
    }

    function liquidate(address tokenAddress , address user , uint256 debtToCover) public morethanzero(debtToCover) nonReentrant {
        uint256 initialHealthFactor = _healthFactor(user);
        if(initialHealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOK();
        }
        uint256 tokenAmount = getTokenAmountFromUsd(debtToCover,tokenAddress);
        uint256 bonusCollateral = (tokenAmount * LIQUIDATION_BONUS) / 100;
        uint256 TotalCollateral = tokenAmount + bonusCollateral;
        _redeemCollateral(user, msg.sender , tokenAddress, TotalCollateral);
        _burnDSC(user, msg.sender, debtToCover);

        uint256 endingHealthFactor = _healthFactor(user);
        if(endingHealthFactor <= initialHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }

        revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns(uint256){
        return _healthFactor(user);
    }


    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthfactor = _healthFactor(user);
        if(healthfactor< MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(healthfactor);
        }
    }

    function _healthFactor(address user) private view returns(uint256){
        (uint256 mintedDSC,uint256 amountCollateral) = getUserInfo(user);
        uint256 collatoralAdjustedForThreshold = (amountCollateral * LIQUIDATION_THRESHOLD)/ LIQUIDATION_PRECISION; 
        return ((collatoralAdjustedForThreshold * PRECISION) /mintedDSC) ;
    }

    function _redeemCollateral(address from, address to, address tokenAddress, uint256 amountCollateral) private {
        s_collatoralDeposited[from][tokenCollateralAddress] -= amount;
        emit CollateralRedeemed (from, to , tokenCollateralAddress , amount);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amount) private {
        s_DscMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
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

    function getTokenAmountFromUsd(uint256 usdAmount, address tokenAddress) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_allPriceFeed[tokenAddress]);
        (,int256 pricee,,,) = priceFeed.latestRoundData();
        return ((usdAmount * PRECISION) / (uint256(pricee) * ADDITIONAL_FEED_PRECISION));
    }
}
