// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
  DeployDSC deployer;
  DecentralizedStableCoin dsc;
  DSCEngine engine;
  HelperConfig config;
  address ethUsdPriceFeed;
  address btcUsdPriceFeed;
  address weth;

  address public USER = makeAddr("user");
  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

  function setUp() public {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth, ,) = config.activeNetworkConfig();

    ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
  }
  ////////////////////////
  // Constructor Tests ///
  ////////////////////////
  address[] public tokenAddresses;
  address[] public priceFeedAddresses;

  function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
    tokenAddresses.push(weth);
    priceFeedAddresses.push(ethUsdPriceFeed);
    priceFeedAddresses.push(btcUsdPriceFeed);

    vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceAddressSameLength.selector);
    new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
  }

  /////////////////
  // Price Tests //
  /////////////////

  function testGetUsdValue() public {
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30000e18;
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(actualUsd, expectedUsd);
  }

  function testGetTokenAmountFromUsd() public {
    uint256 usdAmount = 100 ether;
    uint256 expectedAmount = 0.05 ether;
    uint256 actualAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
    assertEq(actualAmount, expectedAmount);
  }

  //////////////////////
  // Collateral Tests //
  //////////////////////

  function testRevertsIfCollateralZero() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
    vm.expectRevert(DSCEngine.DESCEngine__NeedsMoreThanZero.selector);
    engine.depositCollateral(weth, 0);
    vm.stopPrank();
  }

  function testRevertsWithUnapprovedCollateral() public {
    ERC20Mock ranToken = new ERC20Mock("RAN", "RAN",USER, AMOUNT_COLLATERAL);
    vm.startPrank(USER);
    vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
    engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    vm.stopPrank();
  }
  modifier depositedCollateral() {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
  }

  function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
    uint256 expectedTotalDscMinted = 0;
    uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
    assertEq(totalDscMinted, expectedTotalDscMinted);
    assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
  }
}
