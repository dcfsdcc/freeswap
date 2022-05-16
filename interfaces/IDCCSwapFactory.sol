// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IDCCSwapFactory {
  event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

  function lpFee() external pure returns (uint256);

  function lpFeeToSetter() external view returns (address);

  function lpFeeRateMax() external pure returns (uint256);

  function lpFeeToLpSupplierRate() external view returns (uint256);

  function lpFeeCallBackAddress() external view returns (address);

  function swapFeeCallBackAddress() external view returns (address);

  function feeTo() external pure returns (address);

  function feeToSetter() external view returns (address);

  function getPair(address tokenA, address tokenB) external view returns (address pair);

  function allPairs(uint256) external view returns (address pair);

  function allPairsLength() external view returns (uint256);

  function createPair(address tokenA, address tokenB) external returns (address pair);

  function setFeeTo(address) external;

  function setFeeToSetter(address) external;

  function setLpFeeCallBackAddress(address) external;

  function setLpFee(uint256) external;

  function setLpFeeToSetter(address) external;

  function setLpFeeRateMax(uint256) external;

  function setLpFeeToLpSupplierRate(uint256) external;

  function setSwapFeeCallBackAddress(address) external;

}
