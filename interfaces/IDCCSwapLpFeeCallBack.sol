// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IDCCSwapLpFeeCallBack {
  function AfterLpMintCallBack(
    uint256 feeAmount
  ) external;

  function debugStep(
    uint256 step
  ) external;

  function addFreeByPair(
      address pairAddressParam,
      uint256 freeAmount
  ) external;
}
