const path = require('path');

/**
 * Point React Native autolinking at the SDK source one directory up, so the
 * example consumes the library in-place (no publish / no npm link needed).
 * JS resolution is handled separately by metro.config.js.
 */
module.exports = {
  dependencies: {
    'react-native-mesh-sdk': {
      root: path.resolve(__dirname, '..'),
    },
  },
};
