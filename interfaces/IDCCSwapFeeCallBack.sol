// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IDCCSwapFeeCallBack {
  function AfterSwapFeeCallBack(
      uint256 amountInOrOut,
      uint256[] memory amountFees,
      address[] memory path,
      address _to
  ) external;

  function AfterSwapFeeSupportingFeeOnTransferTokensCallBack(
      uint256 amountInOrOut,
      uint256[] memory amountFees,
      address[] memory path,
      address _to
  ) external;
}
