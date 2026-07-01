const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const exclusionList = require('metro-config/src/defaults/exclusionList');

const root = path.resolve(__dirname, '..');

/**
 * Metro config that lets the example consume the library source directly from
 * the parent folder (so edits to react-native-mesh-sdk hot-reload).
 */
const config = {
  watchFolders: [root],
  resolver: {
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(root, 'node_modules'),
    ],
    extraNodeModules: {
      'react-native-mesh-sdk': root,
    },
    // The vendored Core BitChat (.kt/.swift) and native build dirs are not part
    // of the JS bundle — keep Metro from crawling/watching them.
    blockList: exclusionList([
      new RegExp(`${root.replace(/[/\\]/g, '[/\\\\]')}[/\\\\]android[/\\\\]core[/\\\\].*`),
      new RegExp(`${root.replace(/[/\\]/g, '[/\\\\]')}[/\\\\]ios[/\\\\]core[/\\\\].*`),
      /.*[/\\]android[/\\]build[/\\].*/,
    ]),
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
