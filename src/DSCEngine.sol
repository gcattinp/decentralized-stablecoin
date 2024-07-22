// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/**
 * @title DSCEngine
 * @author Cattin
 * @notice Simple governance contract for Decentralized Stable Coin
 * Pegged to 1 USD
 * Algorithmic minting
 * Exogenous collateral (ETH & BTC)
 * Overcollateralized
 */
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    //////////////
    /// Errors ///
    //////////////
    error DESCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceAddressSameLength();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorTooLow(uint256 healthFactor);
    error DSCEngine__MintFailed();

    ////////////////////////
    /// State Variables ///
    ///////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////
    /// Events ///
    //////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /////////////////
    /// Modifiers ///
    /////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DESCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    /////////////////
    /// Functions ///
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feed
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceAddressSameLength();
        }

        // For other tokens
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    /// External Functions ///
    //////////////////////////
    /*
     * @param tokenCollateralAddress The address of the token to deposit
     * @param amountCollateral The amount of the token to deposit
     * @param amountDscToMint The amount of stablecoin to mint
     * @notice this function will deposit collateral and mint DSC in a single Tx
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral() external {}

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // add a function to revert if DSC minted is higher than collateral deposited
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidtae() external {}

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    /// Private & Internal View Functions ///
    /////////////////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // Total DSC minted
        // Total collateral value
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // Total DSC minted
        // Total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collatralAdjustedForThreshold = ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);
    }

    // 1. Check health factor
    // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow(userHealthFactor);
        }
    }

    /////////////////////////////////////////
    /// Public & External View Functions ///
    /////////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValue) {
        // Loop through each collateral token and get the amount they have deposited
        // mapping it to the price and getting USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += getUsdValue(token, amount);
        }
        return totalCollateralValue;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // The returned value from Chainlink will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}