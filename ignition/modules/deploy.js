const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("DeployAll", (m) => {
  const deployer = m.getAccount(0); // This will act as the owner/treasury

  const initialSupply = m.getParameter("initialSupply", "1000000000000000000000000"); // 1 million KNW (18 decimals)

  const token = m.contract("KnowledgeToken", [initialSupply, deployer]);

  const donation = m.contract("EDonation", [token]);

  const reward = m.contract("RewardContract", [token]);

  return { token, donation, reward };
});
