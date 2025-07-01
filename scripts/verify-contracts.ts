import { execSync } from 'child_process';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// Contract addresses from deployment-addresses.md
const contracts = {
  CollectionRegistry: {
    address: '0xF9fF756360fD6Aea39db9Ab2E998235Dc1F6322F',
    source: 'src/CollectionRegistry.sol:CollectionRegistry',
    description: 'Collection Registry (with correct weight function p1=1e18)'
  },
  CollectionsVault: {
    address: '0x4A4be724F522946296a51d8c82c7C2e8e5a62655',
    source: 'src/CollectionsVault.sol:CollectionsVault',
    description: 'Collections Vault'
  },
  LendingManager: {
    address: '0xb493bEE4C9E0C7d0eC57c38751c9A1c08fAfE434',
    source: 'src/LendingManager.sol:LendingManager',
    description: 'Lending Manager'
  },
  EpochManager: {
    address: '0x5B6dD10DD0fa3454a2749dec1dcBc9e0983620DA',
    source: 'src/EpochManager.sol:EpochManager',
    description: 'Epoch Manager'
  },
  DebtSubsidizer: {
    address: '0xf45CfbC6553BA36328Aba23A4473D4b4a3F569aF',
    source: 'src/DebtSubsidizer.sol:DebtSubsidizer',
    description: 'Debt Subsidizer'
  },
  MockERC20: {
    address: '0x4dd42d4559f7F5026364550FABE7824AECF5a1d1',
    source: 'src/mocks/MockERC20.sol:MockERC20',
    description: 'Mock ERC20 (USDC)'
  },
  MockERC721: {
    address: '0xc7CfdB8290571cAA6DF7d4693059aB9E853e22EB',
    source: 'src/mocks/MockERC721.sol:MockERC721',
    description: 'Mock NFT Collection'
  }
};

// Verification configuration
const config = {
  rpcUrl: 'https://curtis.rpc.caldera.xyz/http',
  verifier: 'blockscout',
  verifierUrl: 'https://curtis.explorer.caldera.xyz/api/',
  explorerUrl: 'https://curtis.explorer.caldera.xyz/address/'
};

interface VerificationResult {
  name: string;
  address: string;
  success: boolean;
  error?: string;
}

async function verifyContract(name: string, contractInfo: any): Promise<VerificationResult> {
  console.log(`\n🔍 Verifying ${contractInfo.description}...`);
  console.log(`   Address: ${contractInfo.address}`);
  console.log(`   Source: ${contractInfo.source}`);

  try {
    const command = `forge verify-contract \\
      --rpc-url "${config.rpcUrl}" \\
      --verifier "${config.verifier}" \\
      --verifier-url "${config.verifierUrl}" \\
      "${contractInfo.address}" \\
      "${contractInfo.source}"`;

    console.log(`   Executing: forge verify-contract...`);
    
    const output = execSync(command, { 
      encoding: 'utf8',
      timeout: 60000, // 60 second timeout
      stdio: 'pipe'
    });

    console.log(`✅ ${contractInfo.description} verified successfully!`);
    console.log(`   Explorer: ${config.explorerUrl}${contractInfo.address}`);
    
    return {
      name,
      address: contractInfo.address,
      success: true
    };

  } catch (error: any) {
    console.log(`❌ Failed to verify ${contractInfo.description}`);
    console.log(`   Error: ${error.message}`);
    
    return {
      name,
      address: contractInfo.address,
      success: false,
      error: error.message
    };
  }
}

async function verifyAllContracts() {
  console.log('🚀 Starting contract verification process...\n');
  console.log('📋 Contracts to verify:');
  
  Object.entries(contracts).forEach(([name, info]) => {
    console.log(`   • ${info.description}: ${info.address}`);
  });

  console.log('\n' + '='.repeat(80));

  const results: VerificationResult[] = [];

  // Verify each contract
  for (const [name, contractInfo] of Object.entries(contracts)) {
    const result = await verifyContract(name, contractInfo);
    results.push(result);
    
    // Wait a bit between verifications to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 2000));
  }

  // Print summary
  console.log('\n' + '='.repeat(80));
  console.log('📊 VERIFICATION SUMMARY');
  console.log('='.repeat(80));

  const successful = results.filter(r => r.success);
  const failed = results.filter(r => !r.success);

  console.log(`✅ Successfully verified: ${successful.length}/${results.length} contracts`);
  
  if (successful.length > 0) {
    console.log('\n🎉 Successfully verified contracts:');
    successful.forEach(result => {
      console.log(`   • ${result.name}: ${config.explorerUrl}${result.address}`);
    });
  }

  if (failed.length > 0) {
    console.log(`\n❌ Failed to verify: ${failed.length} contracts`);
    failed.forEach(result => {
      console.log(`   • ${result.name}: ${result.address}`);
      if (result.error) {
        console.log(`     Error: ${result.error.substring(0, 100)}...`);
      }
    });
  }

  console.log('\n🔗 Key Contract Addresses:');
  console.log(`   Collection Registry: ${contracts.CollectionRegistry.address} (p1=1e18 ✅)`);
  console.log(`   Collections Vault:   ${contracts.CollectionsVault.address}`);
  console.log(`   NFT Collection:      ${contracts.MockERC721.address}`);

  console.log('\n💡 Next Steps:');
  console.log('   1. Check verification status on explorer');
  console.log('   2. Test NFT transfers - they should now accumulate seconds!');
  console.log('   3. Update subgraph with new addresses');

  return {
    total: results.length,
    successful: successful.length,
    failed: failed.length,
    results
  };
}

// Main execution
if (require.main === module) {
  verifyAllContracts()
    .then((summary) => {
      console.log(`\n🏁 Verification completed: ${summary.successful}/${summary.total} successful`);
      process.exit(summary.failed > 0 ? 1 : 0);
    })
    .catch((error) => {
      console.error('💥 Verification process failed:', error);
      process.exit(1);
    });
}

export { verifyAllContracts, contracts, config };