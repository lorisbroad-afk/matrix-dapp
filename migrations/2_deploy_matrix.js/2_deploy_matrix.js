const MatrixDApp = artifacts.require("MatrixDApp");

module.exports = function (deployer) {
  deployer.deploy(MatrixDApp);
};
