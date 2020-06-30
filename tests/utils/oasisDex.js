import { ENCODING_TYPES } from '~/tests/utils/constants';
import { encodeArgs } from '~/tests/utils/formatting';

export const encodeOasisDexTakeOrderArgs = ({
  makerAsset,
  makerQuantity,
  takerAsset,
  takerQuantity,
  orderId,
}, web3) => {
  const args = [makerAsset, makerQuantity, takerAsset, takerQuantity, orderId];
  return encodeArgs(ENCODING_TYPES.OASIS_DEX, args, web3);
};
