// SPDX-License-Identifier: MIT
// Properties that our system should always hold

// What are our invariants?
// 1. The total supply of the DSC should always be less than the total value of the collateral
// 2. Our getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvartiantTest is StdInvariant, Test {
  DeployDSC deployer;
  DSCEngine engine;
  DecentralizedStableCoin dsc;
  HelperConfig config;
  address weth;
  address wbtc;
  Handler handler;

  function setUp() external {
    deployer = new DeployDSC();
    (dsc, engine, config ) = deployer.run();
    (,, weth, wbtc,)= config.activeNetworkConfig();
    handler = new Handler(engine, dsc);
    targetContract(address(handler));
  }

  function invariant_protocolMustHaveMorevalueThanTotalSupply() public view {
    uint256 totalSupply = dsc.totalSupply();

    uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
    uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(engine));

    uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
    uint256 wbtcValue = engine.getUsdValue(wbtc, totalBtcDeposited);

    console.log("weth value: ", wethValue);
    console.log("btc value: ", wbtcValue);
    console.log("total supply: ", totalSupply);
    console.log("Times mint is called", handler.timesMintIsCalled());

    assert(wethValue + wbtcValue >=  totalSupply);
  }

  function invariant_gettersShouldNotRevert() public view {
    engine.getCollateralTokens();
    

  }

}
