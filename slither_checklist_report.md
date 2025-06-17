Summary
 - [incorrect-exp](#incorrect-exp) (1 results) (High)
 - [unchecked-transfer](#unchecked-transfer) (6 results) (High)
 - [divide-before-multiply](#divide-before-multiply) (9 results) (Medium)
 - [erc20-interface](#erc20-interface) (2 results) (Medium)
 - [incorrect-equality](#incorrect-equality) (2 results) (Medium)
 - [reentrancy-no-eth](#reentrancy-no-eth) (10 results) (Medium)
 - [uninitialized-local](#uninitialized-local) (1 results) (Medium)
 - [unused-return](#unused-return) (4 results) (Medium)
 - [shadowing-local](#shadowing-local) (11 results) (Low)
 - [missing-zero-check](#missing-zero-check) (5 results) (Low)
 - [calls-loop](#calls-loop) (7 results) (Low)
 - [reentrancy-benign](#reentrancy-benign) (12 results) (Low)
 - [reentrancy-events](#reentrancy-events) (6 results) (Low)
 - [timestamp](#timestamp) (1 results) (Low)
 - [assembly](#assembly) (61 results) (Informational)
 - [pragma](#pragma) (1 results) (Informational)
 - [costly-loop](#costly-loop) (1 results) (Informational)
 - [dead-code](#dead-code) (19 results) (Informational)
 - [solc-version](#solc-version) (3 results) (Informational)
 - [low-level-calls](#low-level-calls) (1 results) (Informational)
 - [missing-inheritance](#missing-inheritance) (1 results) (Informational)
 - [naming-convention](#naming-convention) (40 results) (Informational)
 - [redundant-statements](#redundant-statements) (1 results) (Informational)
 - [too-many-digits](#too-many-digits) (1 results) (Informational)
 - [unused-state](#unused-state) (6 results) (Informational)
 - [immutable-states](#immutable-states) (11 results) (Optimization)
 - [var-read-using-this](#var-read-using-this) (1 results) (Optimization)
## incorrect-exp
Impact: High
Confidence: Medium
 - [ ] ID-0
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) has bitwise-xor operator ^ instead of the exponentiation operator **: 
	 - [inverse = (3 * denominator) ^ 2](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L257)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


## unchecked-transfer
Impact: High
Confidence: Medium
 - [ ] ID-1
[SimpleMockCToken.repayBorrowBehalf(address,uint256)](src/mocks/SimpleMockCToken.sol#L203-L213) ignores return value by [EIP20Interface(underlying).transferFrom(msg.sender,address(this),repayAmount)](src/mocks/SimpleMockCToken.sol#L204)

src/mocks/SimpleMockCToken.sol#L203-L213


 - [ ] ID-2
[SimpleMockCToken.borrow(uint256)](src/mocks/SimpleMockCToken.sol#L182-L189) ignores return value by [EIP20Interface(underlying).transfer(msg.sender,borrowAmount)](src/mocks/SimpleMockCToken.sol#L186)

src/mocks/SimpleMockCToken.sol#L182-L189


 - [ ] ID-3
[SimpleMockCToken.redeemUnderlying(uint256)](src/mocks/SimpleMockCToken.sol#L174-L180) ignores return value by [EIP20Interface(underlying).transfer(msg.sender,redeemAmount)](src/mocks/SimpleMockCToken.sol#L177)

src/mocks/SimpleMockCToken.sol#L174-L180


 - [ ] ID-4
[SimpleMockCToken.mint(uint256)](src/mocks/SimpleMockCToken.sol#L158-L164) ignores return value by [EIP20Interface(underlying).transferFrom(msg.sender,address(this),mintAmount)](src/mocks/SimpleMockCToken.sol#L160)

src/mocks/SimpleMockCToken.sol#L158-L164


 - [ ] ID-5
[SimpleMockCToken.repayBorrow(uint256)](src/mocks/SimpleMockCToken.sol#L191-L201) ignores return value by [EIP20Interface(underlying).transferFrom(msg.sender,address(this),repayAmount)](src/mocks/SimpleMockCToken.sol#L192)

src/mocks/SimpleMockCToken.sol#L191-L201


 - [ ] ID-6
[SimpleMockCToken.redeem(uint256)](src/mocks/SimpleMockCToken.sol#L166-L172) ignores return value by [EIP20Interface(underlying).transfer(msg.sender,underlyingAmountToReturn)](src/mocks/SimpleMockCToken.sol#L169)

src/mocks/SimpleMockCToken.sol#L166-L172


## divide-before-multiply
Impact: Medium
Confidence: Medium
 - [ ] ID-7
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L261)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-8
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L262)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-9
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L263)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-10
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [low = low / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L245)
	- [result = low * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L272)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-11
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L265)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-12
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse = (3 * denominator) ^ 2](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L257)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-13
[Math.invMod(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L315-L361) performs a multiplication on the result of a division:
	- [quotient = gcd / remainder](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L337)
	- [(gcd,remainder) = (remainder,gcd - remainder * quotient)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L339-L346)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L315-L361


 - [ ] ID-14
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L264)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-15
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L266)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


## erc20-interface
Impact: Medium
Confidence: High
 - [ ] ID-16
[EIP20NonStandardInterface](dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L9-L71) has incorrect ERC20 function interface:[EIP20NonStandardInterface.transferFrom(address,address,uint256)](dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L49)

dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L9-L71


 - [ ] ID-17
[EIP20NonStandardInterface](dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L9-L71) has incorrect ERC20 function interface:[EIP20NonStandardInterface.transfer(address,uint256)](dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L35)

dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L9-L71


## incorrect-equality
Impact: Medium
Confidence: High
 - [ ] ID-18
[LendingManager.redeemAllCTokens(address)](src/LendingManager.sol#L242-L310) uses a dangerous strict equality:
	- [cTokenBalance == 0](src/LendingManager.sol#L253)

src/LendingManager.sol#L242-L310


 - [ ] ID-19
[LendingManager.totalAssets()](src/LendingManager.sol#L189-L196) uses a dangerous strict equality:
	- [cTokenBalance == 0 || rate == 0](src/LendingManager.sol#L192)

src/LendingManager.sol#L189-L196


## reentrancy-no-eth
Impact: Medium
Confidence: Medium
 - [ ] ID-20
Reentrancy in [CollectionsVault.withdrawForCollection(uint256,address,address,address)](src/CollectionsVault.sol#L307-L337):
	External calls:
	- [_hookWithdraw(assets)](src/CollectionsVault.sol#L325)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	State variables written after the call(s):
	- [_withdraw(msg.sender,receiver,owner,assets,shares)](src/CollectionsVault.sol#L326)
		- [_totalSupply += value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L185)
		- [_totalSupply -= value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L200)
	[ERC20._totalSupply](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L34) can be used in cross function reentrancies:
	- [ERC20.totalSupply()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L84-L86)
	- [vaultData.totalAssetsDeposited = currentCollectionTotalAssets - assets](src/CollectionsVault.sol#L328)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalSharesMinted -= shares](src/CollectionsVault.sol#L333)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalCTokensMinted -= shares](src/CollectionsVault.sol#L334)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [totalAssetsDepositedAllCollections -= assets](src/CollectionsVault.sol#L329)
	[CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37) can be used in cross function reentrancies:
	- [CollectionsVault.totalAssets()](src/CollectionsVault.sol#L208-L210)
	- [CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37)

src/CollectionsVault.sol#L307-L337


 - [ ] ID-21
Reentrancy in [CollectionsVault.transferForCollection(address,address,uint256)](src/CollectionsVault.sol#L249-L272):
	External calls:
	- [_hookDeposit(assets)](src/CollectionsVault.sol#L265)
		- [success = lendingManager.depositToLendingProtocol(assets)](src/CollectionsVault.sol#L460)
	State variables written after the call(s):
	- [vaultData.totalAssetsDeposited += assets](src/CollectionsVault.sol#L267)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalSharesMinted += shares](src/CollectionsVault.sol#L269)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalCTokensMinted += shares](src/CollectionsVault.sol#L270)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [totalAssetsDepositedAllCollections += assets](src/CollectionsVault.sol#L268)
	[CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37) can be used in cross function reentrancies:
	- [CollectionsVault.totalAssets()](src/CollectionsVault.sol#L208-L210)
	- [CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37)

src/CollectionsVault.sol#L249-L272


 - [ ] ID-22
Reentrancy in [CollectionsVault.allocateEpochYield(uint256)](src/CollectionsVault.sol#L602-L625):
	External calls:
	- [epochManager.allocateVaultYield(address(this),amount)](src/CollectionsVault.sol#L620)
	State variables written after the call(s):
	- [epochYieldAllocations[currentEpochId] += amount](src/CollectionsVault.sol#L621)
	[CollectionsVault.epochYieldAllocations](src/CollectionsVault.sol#L47) can be used in cross function reentrancies:
	- [CollectionsVault.epochYieldAllocations](src/CollectionsVault.sol#L47)
	- [CollectionsVault.getCurrentEpochYield(bool)](src/CollectionsVault.sol#L576-L600)
	- [CollectionsVault.getEpochYieldAllocated(uint256)](src/CollectionsVault.sol#L643-L645)

src/CollectionsVault.sol#L602-L625


 - [ ] ID-23
Reentrancy in [CollectionsVault.allocateYieldToEpoch(uint256)](src/CollectionsVault.sol#L627-L641):
	External calls:
	- [epochManager.allocateVaultYield(address(this),amount)](src/CollectionsVault.sol#L637)
	State variables written after the call(s):
	- [epochYieldAllocations[epochId] += amount](src/CollectionsVault.sol#L638)
	[CollectionsVault.epochYieldAllocations](src/CollectionsVault.sol#L47) can be used in cross function reentrancies:
	- [CollectionsVault.epochYieldAllocations](src/CollectionsVault.sol#L47)
	- [CollectionsVault.getCurrentEpochYield(bool)](src/CollectionsVault.sol#L576-L600)
	- [CollectionsVault.getEpochYieldAllocated(uint256)](src/CollectionsVault.sol#L643-L645)

src/CollectionsVault.sol#L627-L641


 - [ ] ID-24
Reentrancy in [CollectionsVault.repayBorrowBehalfBatch(uint256[],address[],uint256)](src/CollectionsVault.sol#L523-L574):
	External calls:
	- [_hookWithdraw(totalAmount)](src/CollectionsVault.sol#L539)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	- [lmError = lendingManager.repayBorrowBehalf(borrowerAddr,amt)](src/CollectionsVault.sol#L550)
	State variables written after the call(s):
	- [totalYieldReserved -= actualTotalRepaid](src/CollectionsVault.sol#L569)
	[CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38) can be used in cross function reentrancies:
	- [CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38)
	- [totalYieldReserved = 0](src/CollectionsVault.sol#L571)
	[CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38) can be used in cross function reentrancies:
	- [CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38)

src/CollectionsVault.sol#L523-L574


 - [ ] ID-25
Reentrancy in [CollectionsVault.repayBorrowBehalf(uint256,address)](src/CollectionsVault.sol#L489-L521):
	External calls:
	- [_hookWithdraw(amount)](src/CollectionsVault.sol#L498)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	- [lmError = lendingManager.repayBorrowBehalf(borrower,amount)](src/CollectionsVault.sol#L503)
	State variables written after the call(s):
	- [totalYieldReserved -= amount](src/CollectionsVault.sol#L515)
	[CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38) can be used in cross function reentrancies:
	- [CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38)
	- [totalYieldReserved = 0](src/CollectionsVault.sol#L517)
	[CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38) can be used in cross function reentrancies:
	- [CollectionsVault.totalYieldReserved](src/CollectionsVault.sol#L38)

src/CollectionsVault.sol#L489-L521


 - [ ] ID-26
Reentrancy in [CollectionsVault.redeemForCollection(uint256,address,address,address)](src/CollectionsVault.sol#L343-L409):
	External calls:
	- [_hookWithdraw(assets)](src/CollectionsVault.sol#L365)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	State variables written after the call(s):
	- [_burn(owner,shares)](src/CollectionsVault.sol#L367)
		- [_totalSupply += value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L185)
		- [_totalSupply -= value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L200)
	[ERC20._totalSupply](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L34) can be used in cross function reentrancies:
	- [ERC20.totalSupply()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L84-L86)

src/CollectionsVault.sol#L343-L409


 - [ ] ID-27
Reentrancy in [CollectionsVault.redeemForCollection(uint256,address,address,address)](src/CollectionsVault.sol#L343-L409):
	External calls:
	- [_hookWithdraw(assets)](src/CollectionsVault.sol#L365)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	- [success = lendingManager.withdrawFromLendingProtocol(redeemable)](src/CollectionsVault.sol#L378)
	State variables written after the call(s):
	- [vaultData.totalAssetsDeposited = currentCollectionTotalAssets - assets](src/CollectionsVault.sol#L394)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalAssetsDeposited = 0](src/CollectionsVault.sol#L398)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalSharesMinted -= shares](src/CollectionsVault.sol#L404)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalCTokensMinted -= shares](src/CollectionsVault.sol#L405)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [totalAssetsDepositedAllCollections -= deduction](src/CollectionsVault.sol#L400)
	[CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37) can be used in cross function reentrancies:
	- [CollectionsVault.totalAssets()](src/CollectionsVault.sol#L208-L210)
	- [CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37)

src/CollectionsVault.sol#L343-L409


 - [ ] ID-28
Reentrancy in [CollectionsVault.depositForCollection(uint256,address,address)](src/CollectionsVault.sol#L216-L239):
	External calls:
	- [_hookDeposit(assets)](src/CollectionsVault.sol#L232)
		- [success = lendingManager.depositToLendingProtocol(assets)](src/CollectionsVault.sol#L460)
	State variables written after the call(s):
	- [vaultData.totalAssetsDeposited += assets](src/CollectionsVault.sol#L234)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalSharesMinted += shares](src/CollectionsVault.sol#L236)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalCTokensMinted += shares](src/CollectionsVault.sol#L237)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [totalAssetsDepositedAllCollections += assets](src/CollectionsVault.sol#L235)
	[CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37) can be used in cross function reentrancies:
	- [CollectionsVault.totalAssets()](src/CollectionsVault.sol#L208-L210)
	- [CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37)

src/CollectionsVault.sol#L216-L239


 - [ ] ID-29
Reentrancy in [CollectionsVault.mintForCollection(uint256,address,address)](src/CollectionsVault.sol#L278-L301):
	External calls:
	- [_hookDeposit(assets)](src/CollectionsVault.sol#L294)
		- [success = lendingManager.depositToLendingProtocol(assets)](src/CollectionsVault.sol#L460)
	State variables written after the call(s):
	- [vaultData.totalAssetsDeposited += assets](src/CollectionsVault.sol#L296)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalSharesMinted += shares](src/CollectionsVault.sol#L298)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [vaultData.totalCTokensMinted += shares](src/CollectionsVault.sol#L299)
	[CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36) can be used in cross function reentrancies:
	- [CollectionsVault.collectionTotalAssetsDeposited(address)](src/CollectionsVault.sol#L183-L206)
	- [CollectionsVault.collectionVaultsData](src/CollectionsVault.sol#L36)
	- [totalAssetsDepositedAllCollections += assets](src/CollectionsVault.sol#L297)
	[CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37) can be used in cross function reentrancies:
	- [CollectionsVault.totalAssets()](src/CollectionsVault.sol#L208-L210)
	- [CollectionsVault.totalAssetsDepositedAllCollections](src/CollectionsVault.sol#L37)

src/CollectionsVault.sol#L278-L301


## uninitialized-local
Impact: Medium
Confidence: Medium
 - [ ] ID-30
[LendingManager.repayBorrowBehalf(address,uint256).cTokenError](src/LendingManager.sol#L347) is a local variable never initialized

src/LendingManager.sol#L347


## unused-return
Impact: Medium
Confidence: Medium
 - [ ] ID-31
[LendingManager.constructor(address,address,address,address)](src/LendingManager.sol#L39-L62) ignores return value by [_asset.approve(address(_cToken),type()(uint256).max)](src/LendingManager.sol#L58)

src/LendingManager.sol#L39-L62


 - [ ] ID-32
[AccessControlEnumerable._grantRole(bytes32,address)](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L64-L70) ignores return value by [_roleMembers[role].add(account)](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L67)

dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L64-L70


 - [ ] ID-33
[AccessControlEnumerable._revokeRole(bytes32,address)](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L75-L81) ignores return value by [_roleMembers[role].remove(account)](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L78)

dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L75-L81


 - [ ] ID-34
[MockERC721.mintSpecific(address,uint256)](src/mocks/MockERC721.sol#L36-L50) ignores return value by [this.ownerOf(tokenId)](src/mocks/MockERC721.sol#L39-L44)

src/mocks/MockERC721.sol#L36-L50


## shadowing-local
Impact: Low
Confidence: High
 - [ ] ID-35
[MockFeeOnTransferERC20.constructor(string,string,uint8,uint16,uint16,address).name](src/mocks/MockFeeOnTransferERC20.sol#L14) shadows:
	- [ERC20.name()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L52-L54) (function)
	- [IERC20Metadata.name()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/IERC20Metadata.sol#L15) (function)

src/mocks/MockFeeOnTransferERC20.sol#L14


 - [ ] ID-36
[MockERC20.constructor(string,string,uint8,uint256).name](src/mocks/MockERC20.sol#L14) shadows:
	- [ERC20.name()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L52-L54) (function)
	- [IERC20Metadata.name()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/IERC20Metadata.sol#L15) (function)

src/mocks/MockERC20.sol#L14


 - [ ] ID-37
[MockERC721._balanceOf(address).owner](src/mocks/MockERC721.sol#L53) shadows:
	- [Ownable.owner()](dependencies/@openzeppelin-contracts-5.3.0/access/Ownable.sol#L56-L58) (function)

src/mocks/MockERC721.sol#L53


 - [ ] ID-38
[CollectionsVault.constructor(IERC20,string,string,address,address,address)._symbol](src/CollectionsVault.sol#L60) shadows:
	- [ERC20._symbol](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L37) (state variable)

src/CollectionsVault.sol#L60


 - [ ] ID-39
[CollectionsVault.constructor(IERC20,string,string,address,address,address)._name](src/CollectionsVault.sol#L59) shadows:
	- [ERC20._name](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L36) (state variable)

src/CollectionsVault.sol#L59


 - [ ] ID-40
[MockERC721.constructor(string,string).name](src/mocks/MockERC721.sol#L18) shadows:
	- [ERC721.name()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L74-L76) (function)
	- [IERC721Metadata.name()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/extensions/IERC721Metadata.sol#L16) (function)

src/mocks/MockERC721.sol#L18


 - [ ] ID-41
[MockFeeOnTransferERC20.constructor(string,string,uint8,uint16,uint16,address).symbol](src/mocks/MockFeeOnTransferERC20.sol#L15) shadows:
	- [ERC20.symbol()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L60-L62) (function)
	- [IERC20Metadata.symbol()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/IERC20Metadata.sol#L20) (function)

src/mocks/MockFeeOnTransferERC20.sol#L15


 - [ ] ID-42
[CollectionsVault.redeemForCollection(uint256,address,address,address)._totalSupply](src/CollectionsVault.sol#L358) shadows:
	- [ERC20._totalSupply](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L34) (state variable)

src/CollectionsVault.sol#L358


 - [ ] ID-43
[MockERC721.constructor(string,string).symbol](src/mocks/MockERC721.sol#L18) shadows:
	- [ERC721.symbol()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L81-L83) (function)
	- [IERC721Metadata.symbol()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/extensions/IERC721Metadata.sol#L21) (function)

src/mocks/MockERC721.sol#L18


 - [ ] ID-44
[CollectionsVault.constructor(IERC20,string,string,address,address,address)._asset](src/CollectionsVault.sol#L58) shadows:
	- [ERC4626._asset](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/ERC4626.sol#L51) (state variable)

src/CollectionsVault.sol#L58


 - [ ] ID-45
[MockERC20.constructor(string,string,uint8,uint256).symbol](src/mocks/MockERC20.sol#L14) shadows:
	- [ERC20.symbol()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L60-L62) (function)
	- [IERC20Metadata.symbol()](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/IERC20Metadata.sol#L20) (function)

src/mocks/MockERC20.sol#L14


## missing-zero-check
Impact: Low
Confidence: Medium
 - [ ] ID-46
[SimpleMockCToken.constructor(address,ComptrollerInterface,InterestRateModel,uint256,string,string,uint8,address).admin_](src/mocks/SimpleMockCToken.sol#L66) lacks a zero-check on :
		- [admin = admin_](src/mocks/SimpleMockCToken.sol#L72)

src/mocks/SimpleMockCToken.sol#L66


 - [ ] ID-47
[MockFeeOnTransferERC20.constructor(string,string,uint8,uint16,uint16,address)._feeCollector](src/mocks/MockFeeOnTransferERC20.sol#L19) lacks a zero-check on :
		- [feeCollector = _feeCollector](src/mocks/MockFeeOnTransferERC20.sol#L24)

src/mocks/MockFeeOnTransferERC20.sol#L19


 - [ ] ID-48
[SimpleMockCToken._setPendingAdmin(address).newPendingAdmin](src/mocks/SimpleMockCToken.sol#L338) lacks a zero-check on :
		- [pendingAdmin = newPendingAdmin](src/mocks/SimpleMockCToken.sol#L341)

src/mocks/SimpleMockCToken.sol#L338


 - [ ] ID-49
[SimpleMockCToken.constructor(address,ComptrollerInterface,InterestRateModel,uint256,string,string,uint8,address).underlyingAddress_](src/mocks/SimpleMockCToken.sol#L59) lacks a zero-check on :
		- [underlying = underlyingAddress_](src/mocks/SimpleMockCToken.sol#L85)

src/mocks/SimpleMockCToken.sol#L59


 - [ ] ID-50
[EpochManager.constructor(uint256,address,address)._initialAutomatedSystem](src/EpochManager.sol#L153) lacks a zero-check on :
		- [automatedSystem = _initialAutomatedSystem](src/EpochManager.sol#L160)

src/EpochManager.sol#L153


## calls-loop
Impact: Low
Confidence: Medium
 - [ ] ID-51
[DebtSubsidizer._claimSubsidy(address,IDebtSubsidizer.ClaimData)](src/DebtSubsidizer.sol#L151-L195) has external calls inside a loop: [em = ICollectionsVault(vaultAddress).epochManager()](src/DebtSubsidizer.sol#L183)
	Calls stack containing the loop:
		DebtSubsidizer.claimAllSubsidies(address[],IDebtSubsidizer.ClaimData[])

src/DebtSubsidizer.sol#L151-L195


 - [ ] ID-52
[CollectionsVault.repayBorrowBehalfBatch(uint256[],address[],uint256)](src/CollectionsVault.sol#L523-L574) has external calls inside a loop: [lmError = lendingManager.repayBorrowBehalf(borrowerAddr,amt)](src/CollectionsVault.sol#L550)

src/CollectionsVault.sol#L523-L574


 - [ ] ID-53
[CollectionsVault.totalCollectionYieldShareBps()](src/CollectionsVault.sol#L647-L655) has external calls inside a loop: [totalBps += collectionRegistry.getCollection(allCollectionAddresses[i]).yieldSharePercentage](src/CollectionsVault.sol#L650)

src/CollectionsVault.sol#L647-L655


 - [ ] ID-54
[DebtSubsidizer._claimSubsidy(address,IDebtSubsidizer.ClaimData)](src/DebtSubsidizer.sol#L151-L195) has external calls inside a loop: [epochId = em.getCurrentEpochId()](src/DebtSubsidizer.sol#L184)
	Calls stack containing the loop:
		DebtSubsidizer.claimAllSubsidies(address[],IDebtSubsidizer.ClaimData[])

src/DebtSubsidizer.sol#L151-L195


 - [ ] ID-55
[CollectionsVault._accrueCollectionYield(address)](src/CollectionsVault.sol#L99-L127) has external calls inside a loop: [registryCollection = collectionRegistry.getCollection(collectionAddress)](src/CollectionsVault.sol#L103)
	Calls stack containing the loop:
		CollectionsVault.indexCollectionsDeposits()

src/CollectionsVault.sol#L99-L127


 - [ ] ID-56
[DebtSubsidizer._claimSubsidy(address,IDebtSubsidizer.ClaimData)](src/DebtSubsidizer.sol#L151-L195) has external calls inside a loop: [remainingYield = ICollectionsVault(vaultAddress).getEpochYieldAllocated(epochId)](src/DebtSubsidizer.sol#L185)
	Calls stack containing the loop:
		DebtSubsidizer.claimAllSubsidies(address[],IDebtSubsidizer.ClaimData[])

src/DebtSubsidizer.sol#L151-L195


 - [ ] ID-57
[DebtSubsidizer._claimSubsidy(address,IDebtSubsidizer.ClaimData)](src/DebtSubsidizer.sol#L151-L195) has external calls inside a loop: [ICollectionsVault(vaultAddress).repayBorrowBehalf(amountToSubsidize,recipient)](src/DebtSubsidizer.sol#L193)
	Calls stack containing the loop:
		DebtSubsidizer.claimAllSubsidies(address[],IDebtSubsidizer.ClaimData[])

src/DebtSubsidizer.sol#L151-L195


## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-58
Reentrancy in [CollectionsVault.repayBorrowBehalfBatch(uint256[],address[],uint256)](src/CollectionsVault.sol#L523-L574):
	External calls:
	- [_hookWithdraw(totalAmount)](src/CollectionsVault.sol#L539)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	- [lmError = lendingManager.repayBorrowBehalf(borrowerAddr,amt)](src/CollectionsVault.sol#L550)
	State variables written after the call(s):
	- [epochYieldAllocations[epochId] -= actualTotalRepaid](src/CollectionsVault.sol#L565)

src/CollectionsVault.sol#L523-L574


 - [ ] ID-59
Reentrancy in [SimpleMockCToken.repayBorrowBehalf(address,uint256)](src/mocks/SimpleMockCToken.sol#L203-L213):
	External calls:
	- [EIP20Interface(underlying).transferFrom(msg.sender,address(this),repayAmount)](src/mocks/SimpleMockCToken.sol#L204)
	State variables written after the call(s):
	- [accountBorrows[borrower].principal -= actualRepayAmount](src/mocks/SimpleMockCToken.sol#L208)

src/mocks/SimpleMockCToken.sol#L203-L213


 - [ ] ID-60
Reentrancy in [LendingManager.updateExchangeRate()](src/LendingManager.sol#L365-L369):
	External calls:
	- [newRate = CTokenInterface(address(_cToken)).exchangeRateCurrent()](src/LendingManager.sol#L366)
	State variables written after the call(s):
	- [cachedExchangeRate = newRate](src/LendingManager.sol#L367)
	- [lastExchangeRateTimestamp = block.timestamp](src/LendingManager.sol#L368)

src/LendingManager.sol#L365-L369


 - [ ] ID-61
Reentrancy in [SimpleMockCToken.mint(uint256)](src/mocks/SimpleMockCToken.sol#L158-L164):
	External calls:
	- [EIP20Interface(underlying).transferFrom(msg.sender,address(this),mintAmount)](src/mocks/SimpleMockCToken.sol#L160)
	State variables written after the call(s):
	- [_mintTokens(msg.sender,cTokensToMint)](src/mocks/SimpleMockCToken.sol#L161)
		- [accountTokens[minter] += amount](src/mocks/SimpleMockCToken.sol#L143)
	- [_mintTokens(msg.sender,cTokensToMint)](src/mocks/SimpleMockCToken.sol#L161)
		- [totalSupply += amount](src/mocks/SimpleMockCToken.sol#L142)

src/mocks/SimpleMockCToken.sol#L158-L164


 - [ ] ID-62
Reentrancy in [CollectionsVault.allocateYieldToEpoch(uint256)](src/CollectionsVault.sol#L627-L641):
	External calls:
	- [epochManager.allocateVaultYield(address(this),amount)](src/CollectionsVault.sol#L637)
	State variables written after the call(s):
	- [totalYieldReserved += amount](src/CollectionsVault.sol#L639)

src/CollectionsVault.sol#L627-L641


 - [ ] ID-63
Reentrancy in [CollectionsVault.repayBorrowBehalf(uint256,address)](src/CollectionsVault.sol#L489-L521):
	External calls:
	- [_hookWithdraw(amount)](src/CollectionsVault.sol#L498)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	- [lmError = lendingManager.repayBorrowBehalf(borrower,amount)](src/CollectionsVault.sol#L503)
	State variables written after the call(s):
	- [epochYieldAllocations[epochId] -= amount](src/CollectionsVault.sol#L511)

src/CollectionsVault.sol#L489-L521


 - [ ] ID-64
Reentrancy in [CollectionsVault.redeemForCollection(uint256,address,address,address)](src/CollectionsVault.sol#L343-L409):
	External calls:
	- [_hookWithdraw(assets)](src/CollectionsVault.sol#L365)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	State variables written after the call(s):
	- [_spendAllowance(owner,msg.sender,shares)](src/CollectionsVault.sol#L366)
		- [_allowances[owner][spender] = value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L286)
	- [_burn(owner,shares)](src/CollectionsVault.sol#L367)
		- [_balances[from] = fromBalance - value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L193)
		- [_balances[to] += value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L205)

src/CollectionsVault.sol#L343-L409


 - [ ] ID-65
Reentrancy in [CollectionsVault.allocateEpochYield(uint256)](src/CollectionsVault.sol#L602-L625):
	External calls:
	- [epochManager.allocateVaultYield(address(this),amount)](src/CollectionsVault.sol#L620)
	State variables written after the call(s):
	- [totalYieldReserved += amount](src/CollectionsVault.sol#L622)

src/CollectionsVault.sol#L602-L625


 - [ ] ID-66
Reentrancy in [SimpleMockCToken.repayBorrow(uint256)](src/mocks/SimpleMockCToken.sol#L191-L201):
	External calls:
	- [EIP20Interface(underlying).transferFrom(msg.sender,address(this),repayAmount)](src/mocks/SimpleMockCToken.sol#L192)
	State variables written after the call(s):
	- [accountBorrows[msg.sender].principal -= actualRepayAmount](src/mocks/SimpleMockCToken.sol#L196)

src/mocks/SimpleMockCToken.sol#L191-L201


 - [ ] ID-67
Reentrancy in [CollectionsVault.withdrawForCollection(uint256,address,address,address)](src/CollectionsVault.sol#L307-L337):
	External calls:
	- [_hookWithdraw(assets)](src/CollectionsVault.sol#L325)
		- [success = lendingManager.withdrawFromLendingProtocol(neededFromLM)](src/CollectionsVault.sol#L478)
	State variables written after the call(s):
	- [_withdraw(msg.sender,receiver,owner,assets,shares)](src/CollectionsVault.sol#L326)
		- [_allowances[owner][spender] = value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L286)
	- [_withdraw(msg.sender,receiver,owner,assets,shares)](src/CollectionsVault.sol#L326)
		- [_balances[from] = fromBalance - value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L193)
		- [_balances[to] += value](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L205)

src/CollectionsVault.sol#L307-L337


 - [ ] ID-68
Reentrancy in [LendingManager.depositToLendingProtocol(uint256)](src/LendingManager.sol#L87-L130):
	External calls:
	- [mintResult = _cToken.mint(amount)](src/LendingManager.sol#L109-L117)
	State variables written after the call(s):
	- [totalPrincipalDeposited += amount](src/LendingManager.sol#L126)

src/LendingManager.sol#L87-L130


 - [ ] ID-69
Reentrancy in [LendingManager.withdrawFromLendingProtocol(uint256)](src/LendingManager.sol#L132-L187):
	External calls:
	- [accrualResult = CTokenInterface(address(_cToken)).accrueInterest()](src/LendingManager.sol#L142)
	- [redeemResult = _cToken.redeemUnderlying(amount)](src/LendingManager.sol#L151-L159)
	State variables written after the call(s):
	- [totalPrincipalDeposited -= amount](src/LendingManager.sol#L179)
	- [totalPrincipalDeposited = 0](src/LendingManager.sol#L182)

src/LendingManager.sol#L132-L187


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-70
Reentrancy in [SimpleMockCToken.repayBorrowBehalf(address,uint256)](src/mocks/SimpleMockCToken.sol#L203-L213):
	External calls:
	- [EIP20Interface(underlying).transferFrom(msg.sender,address(this),repayAmount)](src/mocks/SimpleMockCToken.sol#L204)
	Event emitted after the call(s):
	- [RepayBorrow(msg.sender,borrower,actualRepayAmount,accountBorrows[borrower].principal,CTokenStorage.totalBorrows)](src/mocks/SimpleMockCToken.sol#L209-L211)

src/mocks/SimpleMockCToken.sol#L203-L213


 - [ ] ID-71
Reentrancy in [SimpleMockCToken.mint(uint256)](src/mocks/SimpleMockCToken.sol#L158-L164):
	External calls:
	- [EIP20Interface(underlying).transferFrom(msg.sender,address(this),mintAmount)](src/mocks/SimpleMockCToken.sol#L160)
	Event emitted after the call(s):
	- [Mint(msg.sender,mintAmount,cTokensToMint)](src/mocks/SimpleMockCToken.sol#L162)

src/mocks/SimpleMockCToken.sol#L158-L164


 - [ ] ID-72
Reentrancy in [SimpleMockCToken.repayBorrow(uint256)](src/mocks/SimpleMockCToken.sol#L191-L201):
	External calls:
	- [EIP20Interface(underlying).transferFrom(msg.sender,address(this),repayAmount)](src/mocks/SimpleMockCToken.sol#L192)
	Event emitted after the call(s):
	- [RepayBorrow(msg.sender,msg.sender,actualRepayAmount,accountBorrows[msg.sender].principal,CTokenStorage.totalBorrows)](src/mocks/SimpleMockCToken.sol#L197-L199)

src/mocks/SimpleMockCToken.sol#L191-L201


 - [ ] ID-73
Reentrancy in [SimpleMockCToken.redeemUnderlying(uint256)](src/mocks/SimpleMockCToken.sol#L174-L180):
	External calls:
	- [EIP20Interface(underlying).transfer(msg.sender,redeemAmount)](src/mocks/SimpleMockCToken.sol#L177)
	Event emitted after the call(s):
	- [Redeem(msg.sender,redeemAmount,cTokensToBurn)](src/mocks/SimpleMockCToken.sol#L178)

src/mocks/SimpleMockCToken.sol#L174-L180


 - [ ] ID-74
Reentrancy in [SimpleMockCToken.borrow(uint256)](src/mocks/SimpleMockCToken.sol#L182-L189):
	External calls:
	- [EIP20Interface(underlying).transfer(msg.sender,borrowAmount)](src/mocks/SimpleMockCToken.sol#L186)
	Event emitted after the call(s):
	- [Borrow(msg.sender,borrowAmount,accountBorrows[msg.sender].principal,CTokenStorage.totalBorrows)](src/mocks/SimpleMockCToken.sol#L187)

src/mocks/SimpleMockCToken.sol#L182-L189


 - [ ] ID-75
Reentrancy in [SimpleMockCToken.redeem(uint256)](src/mocks/SimpleMockCToken.sol#L166-L172):
	External calls:
	- [EIP20Interface(underlying).transfer(msg.sender,underlyingAmountToReturn)](src/mocks/SimpleMockCToken.sol#L169)
	Event emitted after the call(s):
	- [Redeem(msg.sender,underlyingAmountToReturn,redeemCTokens)](src/mocks/SimpleMockCToken.sol#L170)

src/mocks/SimpleMockCToken.sol#L166-L172


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-76
[EpochManager.beginEpochProcessing(uint256)](src/EpochManager.sol#L223-L239) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp < epoch.endTime](src/EpochManager.sol#L232)

src/EpochManager.sol#L223-L239


## assembly
Impact: Informational
Confidence: High
 - [ ] ID-77
[PausableUpgradeable._getPausableStorage()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L27-L31) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L28-L30)

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L27-L31


 - [ ] ID-78
[Hashes.efficientKeccak256(bytes32,bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/Hashes.sol#L24-L30) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/Hashes.sol#L25-L29)

dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/Hashes.sol#L24-L30


 - [ ] ID-79
[Arrays._castToUint256Comp(function(address,address) returns(bool))](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L194-L200) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L197-L199)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L194-L200


 - [ ] ID-80
[Arrays.unsafeSetLength(uint256[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L477-L481) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L478-L480)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L477-L481


 - [ ] ID-81
[Arrays.unsafeSetLength(address[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L455-L459) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L456-L458)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L455-L459


 - [ ] ID-82
[StorageSlot.getBooleanSlot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L75-L79) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L76-L78)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L75-L79


 - [ ] ID-83
[ReentrancyGuardUpgradeable._getReentrancyGuardStorage()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L49-L53) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L50-L52)

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L49-L53


 - [ ] ID-84
[Arrays.unsafeSetLength(bytes32[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L466-L470) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L467-L469)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L466-L470


 - [ ] ID-85
[Arrays._castToUint256Comp(function(bytes32,bytes32) returns(bool))](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L203-L209) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L206-L208)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L203-L209


 - [ ] ID-86
[SlotDerivation.deriveMapping(bytes32,string)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L129-L139) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L130-L138)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L129-L139


 - [ ] ID-87
[SlotDerivation.deriveMapping(bytes32,address)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L74-L80) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L75-L79)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L74-L80


 - [ ] ID-88
[Panic.panic(uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Panic.sol#L50-L56) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Panic.sol#L51-L55)

dependencies/@openzeppelin-contracts-5.3.0/utils/Panic.sol#L50-L56


 - [ ] ID-89
[Arrays.unsafeMemoryAccess(uint256[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L444-L448) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L445-L447)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L444-L448


 - [ ] ID-90
[StorageSlot.getBytesSlot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L129-L133) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L130-L132)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L129-L133


 - [ ] ID-91
[Arrays.unsafeAccess(uint256[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L409-L415) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L411-L413)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L409-L415


 - [ ] ID-92
[EnumerableSet.values(EnumerableSet.Bytes32Set)](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L246-L255) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L250-L252)

dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L246-L255


 - [ ] ID-93
[Arrays.unsafeMemoryAccess(address[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L422-L426) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L423-L425)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L422-L426


 - [ ] ID-94
[SlotDerivation.deriveArray(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L64-L69) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L65-L68)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L64-L69


 - [ ] ID-95
[SlotDerivation.deriveMapping(bytes32,bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L96-L102) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L97-L101)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L96-L102


 - [ ] ID-96
[ERC165Checker.supportsERC165InterfaceUnchecked(address,bytes4)](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165Checker.sol#L108-L123) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165Checker.sol#L116-L120)

dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165Checker.sol#L108-L123


 - [ ] ID-97
[Arrays.unsafeAccess(address[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L383-L389) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L385-L387)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L383-L389


 - [ ] ID-98
[EnumerableSet.values(EnumerableSet.UintSet)](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L412-L421) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L416-L418)

dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L412-L421


 - [ ] ID-99
[SlotDerivation.deriveMapping(bytes32,bool)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L85-L91) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L86-L90)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L85-L91


 - [ ] ID-100
[Arrays._swap(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L170-L177) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L171-L176)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L170-L177


 - [ ] ID-101
[ERC721Utils.checkOnERC721Received(address,address,address,uint256,bytes)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/utils/ERC721Utils.sol#L25-L49) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/utils/ERC721Utils.sol#L43-L45)

dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/utils/ERC721Utils.sol#L25-L49


 - [ ] ID-102
[StorageSlot.getStringSlot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L111-L115) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L112-L114)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L111-L115


 - [ ] ID-103
[Arrays.unsafeMemoryAccess(bytes32[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L433-L437) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L434-L436)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L433-L437


 - [ ] ID-104
[Initializable._getInitializableStorage()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L232-L237) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L234-L236)

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L232-L237


 - [ ] ID-105
[SafeERC20._callOptionalReturnBool(IERC20,bytes)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L201-L211) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L205-L209)

dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L201-L211


 - [ ] ID-106
[Math.mul512(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L37-L46) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L41-L45)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L37-L46


 - [ ] ID-107
[SafeCast.toUint(bool)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/SafeCast.sol#L1157-L1161) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/SafeCast.sol#L1158-L1160)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/SafeCast.sol#L1157-L1161


 - [ ] ID-108
[Strings.toString(uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L45-L63) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L50-L52)
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L55-L57)

dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L45-L63


 - [ ] ID-109
[Math.tryDiv(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L89-L97) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L92-L95)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L89-L97


 - [ ] ID-110
[Math.mulDiv(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L227-L234)
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L240-L249)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L204-L275


 - [ ] ID-111
[StorageSlot.getStringSlot(string)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L120-L124) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L121-L123)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L120-L124


 - [ ] ID-112
[Strings.escapeJSON(string)](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L446-L476) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L470-L473)

dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L446-L476


 - [ ] ID-113
[EnumerableSet.values(EnumerableSet.AddressSet)](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L329-L338) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L333-L335)

dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L329-L338


 - [ ] ID-114
[SafeERC20._callOptionalReturn(IERC20,bytes)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L173-L191) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L176-L186)

dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L173-L191


 - [ ] ID-115
[Math.add512(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L25-L30) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L26-L29)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L25-L30


 - [ ] ID-116
[StorageSlot.getAddressSlot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L66-L70) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L67-L69)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L66-L70


 - [ ] ID-117
[Math.log2(uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L612-L651) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L648-L650)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L612-L651


 - [ ] ID-118
[Arrays.unsafeAccess(bytes32[],uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L396-L402) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L398-L400)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L396-L402


 - [ ] ID-119
[Arrays._begin(uint256[])](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L142-L146) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L143-L145)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L142-L146


 - [ ] ID-120
[Arrays._castToUint256Array(bytes32[])](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L187-L191) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L188-L190)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L187-L191


 - [ ] ID-121
[StorageSlot.getUint256Slot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L93-L97) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L94-L96)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L93-L97


 - [ ] ID-122
[StorageSlot.getBytesSlot(bytes)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L138-L142) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L139-L141)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L138-L142


 - [ ] ID-123
[Math.tryModExp(bytes,bytes,bytes)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L449-L471) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L461-L470)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L449-L471


 - [ ] ID-124
[Math.tryMul(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L73-L84) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L76-L80)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L73-L84


 - [ ] ID-125
[SlotDerivation.erc7201Slot(string)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L45-L50) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L46-L49)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L45-L50


 - [ ] ID-126
[Strings.toChecksumHexString(address)](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L111-L129) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L116-L118)

dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L111-L129


 - [ ] ID-127
[Math.tryMod(uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L102-L110) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L105-L108)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L102-L110


 - [ ] ID-128
[StorageSlot.getBytes32Slot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L84-L88) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L85-L87)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L84-L88


 - [ ] ID-129
[Arrays._castToUint256Array(address[])](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L180-L184) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L181-L183)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L180-L184


 - [ ] ID-130
[Strings._unsafeReadBytesOffset(bytes,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L484-L489) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L486-L488)

dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L484-L489


 - [ ] ID-131
[Arrays._mload(uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L161-L165) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L162-L164)

dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L161-L165


 - [ ] ID-132
[SlotDerivation.deriveMapping(bytes32,int256)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L118-L124) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L119-L123)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L118-L124


 - [ ] ID-133
[SlotDerivation.deriveMapping(bytes32,bytes)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L144-L154) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L145-L153)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L144-L154


 - [ ] ID-134
[Math.tryModExp(uint256,uint256,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L409-L433) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L411-L432)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L409-L433


 - [ ] ID-135
[OwnableUpgradeable._getOwnableStorage()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L30-L34) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L31-L33)

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L30-L34


 - [ ] ID-136
[StorageSlot.getInt256Slot(bytes32)](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L102-L106) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L103-L105)

dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L102-L106


 - [ ] ID-137
[SlotDerivation.deriveMapping(bytes32,uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L107-L113) uses assembly
	- [INLINE ASM](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L108-L112)

dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L107-L113


## pragma
Impact: Informational
Confidence: High
 - [ ] ID-138
3 different versions of Solidity are used:
	- Version constraint ^0.8.20 is used by:
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/AccessControl.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/IAccessControl.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/Ownable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/IAccessControlEnumerable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC1363.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC165.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC20.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC4626.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/draft-IERC6093.sol#L3)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC1155/IERC1155.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/ERC4626.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/IERC20Metadata.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/IERC721.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/IERC721Receiver.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/extensions/IERC721Metadata.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/utils/ERC721Utils.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L5)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Comparators.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Context.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Panic.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Pausable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/ReentrancyGuard.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L5)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L5)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/Hashes.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/MerkleProof.sol#L5)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165Checker.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/IERC165.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/math/SafeCast.sol#L5)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/math/SignedMath.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L5)
		-[^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L4)
		-[^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L4)
		-[^0.8.20](src/CollectionRegistry.sol#L2)
		-[^0.8.20](src/CollectionsVault.sol#L2)
		-[^0.8.20](src/DebtSubsidizer.sol#L2)
		-[^0.8.20](src/EpochManager.sol#L2)
		-[^0.8.20](src/LendingManager.sol#L2)
		-[^0.8.20](src/Roles.sol#L2)
		-[^0.8.20](src/interfaces/ICollectionRegistry.sol#L2)
		-[^0.8.20](src/interfaces/ICollectionsVault.sol#L2)
		-[^0.8.20](src/interfaces/IEpochManager.sol#L2)
		-[^0.8.20](src/interfaces/ILendingManager.sol#L2)
		-[^0.8.20](src/mocks/MockERC20.sol#L2)
		-[^0.8.20](src/mocks/MockERC721.sol#L2)
	- Version constraint ^0.8.10 is used by:
		-[^0.8.10](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L2)
		-[^0.8.10](dependencies/compound-protocol-2.8.1/contracts/ComptrollerInterface.sol#L2)
		-[^0.8.10](dependencies/compound-protocol-2.8.1/contracts/EIP20Interface.sol#L2)
		-[^0.8.10](dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L2)
		-[^0.8.10](dependencies/compound-protocol-2.8.1/contracts/ErrorReporter.sol#L2)
		-[^0.8.10](dependencies/compound-protocol-2.8.1/contracts/InterestRateModel.sol#L2)
		-[^0.8.10](src/mocks/SimpleMockCToken.sol#L2)
	- Version constraint ^0.8.19 is used by:
		-[^0.8.19](src/interfaces/IDebtSubsidizer.sol#L2)
		-[^0.8.19](src/mocks/MockFeeOnTransferERC20.sol#L2)

dependencies/@openzeppelin-contracts-5.3.0/access/AccessControl.sol#L4


## costly-loop
Impact: Informational
Confidence: Medium
 - [ ] ID-139
[CollectionsVault._accrueCollectionYield(address)](src/CollectionsVault.sol#L99-L127) has costly operations inside a loop:
	- [totalAssetsDepositedAllCollections += yieldAccrued](src/CollectionsVault.sol#L120)
	Calls stack containing the loop:
		CollectionsVault.indexCollectionsDeposits()

src/CollectionsVault.sol#L99-L127


## dead-code
Impact: Informational
Confidence: Medium
 - [ ] ID-140
[ContextUpgradeable._msgData()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L27-L29) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L27-L29


 - [ ] ID-141
[AccessControl._setRoleAdmin(bytes32,bytes32)](dependencies/@openzeppelin-contracts-5.3.0/access/AccessControl.sol#L170-L174) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/access/AccessControl.sol#L170-L174


 - [ ] ID-142
[Context._contextSuffixLength()](dependencies/@openzeppelin-contracts-5.3.0/utils/Context.sol#L25-L27) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/utils/Context.sol#L25-L27


 - [ ] ID-143
[ERC721._safeTransfer(address,address,uint256,bytes)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L386-L389) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L386-L389


 - [ ] ID-144
[ContextUpgradeable._contextSuffixLength()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L31-L33) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L31-L33


 - [ ] ID-145
[ComptrollerErrorReporter.fail(ComptrollerErrorReporter.Error,ComptrollerErrorReporter.FailureInfo)](dependencies/compound-protocol-2.8.1/contracts/ErrorReporter.sol#L58-L62) is never used and should be removed

dependencies/compound-protocol-2.8.1/contracts/ErrorReporter.sol#L58-L62


 - [ ] ID-146
[ERC721._transfer(address,address,uint256)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L347-L357) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L347-L357


 - [ ] ID-147
[ContextUpgradeable.__Context_init_unchained()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L21-L22) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L21-L22


 - [ ] ID-148
[ERC721._burn(uint256)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L329-L334) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L329-L334


 - [ ] ID-149
[MockERC721._balanceOf(address)](src/mocks/MockERC721.sol#L53-L55) is never used and should be removed

src/mocks/MockERC721.sol#L53-L55


 - [ ] ID-150
[ComptrollerErrorReporter.failOpaque(ComptrollerErrorReporter.Error,ComptrollerErrorReporter.FailureInfo,uint256)](dependencies/compound-protocol-2.8.1/contracts/ErrorReporter.sol#L67-L71) is never used and should be removed

dependencies/compound-protocol-2.8.1/contracts/ErrorReporter.sol#L67-L71


 - [ ] ID-151
[ReentrancyGuardUpgradeable._reentrancyGuardEntered()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L104-L107) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L104-L107


 - [ ] ID-152
[Context._msgData()](dependencies/@openzeppelin-contracts-5.3.0/utils/Context.sol#L21-L23) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/utils/Context.sol#L21-L23


 - [ ] ID-153
[Initializable._getInitializedVersion()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L208-L210) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L208-L210


 - [ ] ID-154
[ERC721._safeTransfer(address,address,uint256)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L378-L380) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L378-L380


 - [ ] ID-155
[ReentrancyGuard._reentrancyGuardEntered()](dependencies/@openzeppelin-contracts-5.3.0/utils/ReentrancyGuard.sol#L84-L86) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/utils/ReentrancyGuard.sol#L84-L86


 - [ ] ID-156
[ERC721._increaseBalance(address,uint128)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L225-L229) is never used and should be removed

dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L225-L229


 - [ ] ID-157
[PausableUpgradeable.__Pausable_init_unchained()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L80-L81) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L80-L81


 - [ ] ID-158
[ContextUpgradeable.__Context_init()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L18-L19) is never used and should be removed

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L18-L19


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-159
Version constraint ^0.8.19 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess.
It is used by:
	- [^0.8.19](src/interfaces/IDebtSubsidizer.sol#L2)
	- [^0.8.19](src/mocks/MockFeeOnTransferERC20.sol#L2)

src/interfaces/IDebtSubsidizer.sol#L2


 - [ ] ID-160
Version constraint ^0.8.20 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess.
It is used by:
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/AccessControl.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/IAccessControl.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/Ownable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/AccessControlEnumerable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/access/extensions/IAccessControlEnumerable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC1363.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC165.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC20.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/IERC4626.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/interfaces/draft-IERC6093.sol#L3)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC1155/IERC1155.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/ERC20.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/ERC4626.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/IERC20Metadata.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/IERC721.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/IERC721Receiver.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/extensions/IERC721Metadata.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/token/ERC721/utils/ERC721Utils.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Arrays.sol#L5)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Comparators.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Context.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Panic.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Pausable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/ReentrancyGuard.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/SlotDerivation.sol#L5)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/StorageSlot.sol#L5)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/Strings.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/Hashes.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/cryptography/MerkleProof.sol#L5)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/ERC165Checker.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/introspection/IERC165.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/math/SafeCast.sol#L5)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/math/SignedMath.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol#L5)
	- [^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L4)
	- [^0.8.20](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L4)
	- [^0.8.20](src/CollectionRegistry.sol#L2)
	- [^0.8.20](src/CollectionsVault.sol#L2)
	- [^0.8.20](src/DebtSubsidizer.sol#L2)
	- [^0.8.20](src/EpochManager.sol#L2)
	- [^0.8.20](src/LendingManager.sol#L2)
	- [^0.8.20](src/Roles.sol#L2)
	- [^0.8.20](src/interfaces/ICollectionRegistry.sol#L2)
	- [^0.8.20](src/interfaces/ICollectionsVault.sol#L2)
	- [^0.8.20](src/interfaces/IEpochManager.sol#L2)
	- [^0.8.20](src/interfaces/ILendingManager.sol#L2)
	- [^0.8.20](src/mocks/MockERC20.sol#L2)
	- [^0.8.20](src/mocks/MockERC721.sol#L2)

dependencies/@openzeppelin-contracts-5.3.0/access/AccessControl.sol#L4


 - [ ] ID-161
Version constraint ^0.8.10 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- DataLocationChangeInInternalOverride
	- NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
	- [^0.8.10](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L2)
	- [^0.8.10](dependencies/compound-protocol-2.8.1/contracts/ComptrollerInterface.sol#L2)
	- [^0.8.10](dependencies/compound-protocol-2.8.1/contracts/EIP20Interface.sol#L2)
	- [^0.8.10](dependencies/compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol#L2)
	- [^0.8.10](dependencies/compound-protocol-2.8.1/contracts/ErrorReporter.sol#L2)
	- [^0.8.10](dependencies/compound-protocol-2.8.1/contracts/InterestRateModel.sol#L2)
	- [^0.8.10](src/mocks/SimpleMockCToken.sol#L2)

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L2


## low-level-calls
Impact: Informational
Confidence: High
 - [ ] ID-162
Low level call in [ERC4626._tryGetAssetDecimals(IERC20)](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/ERC4626.sol#L86-L97):
	- [(success,encodedDecimals) = address(asset_).staticcall(abi.encodeCall(IERC20Metadata.decimals,()))](dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/ERC4626.sol#L87-L89)

dependencies/@openzeppelin-contracts-5.3.0/token/ERC20/extensions/ERC4626.sol#L86-L97


## missing-inheritance
Impact: Informational
Confidence: High
 - [ ] ID-163
[EpochManager](src/EpochManager.sol#L15-L427) should inherit from [IEpochManager](src/interfaces/IEpochManager.sol#L4-L7)

src/EpochManager.sol#L15-L427


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-164
Function [SimpleMockCToken._setInterestRateModel(InterestRateModel)](src/mocks/SimpleMockCToken.sol#L386-L397) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L386-L397


 - [ ] ID-165
Function [ICollectionsVault.DEBT_SUBSIDIZER_ROLE()](src/interfaces/ICollectionsVault.sol#L106) is not in mixedCase

src/interfaces/ICollectionsVault.sol#L106


 - [ ] ID-166
Parameter [MockFeeOnTransferERC20.setFeeBpsReceive(uint16)._newFeeBps](src/mocks/MockFeeOnTransferERC20.sol#L92) is not in mixedCase

src/mocks/MockFeeOnTransferERC20.sol#L92


 - [ ] ID-167
Constant [CTokenStorage.borrowRateMaxMantissa](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L31) is not in UPPER_CASE_WITH_UNDERSCORES

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L31


 - [ ] ID-168
Parameter [CollectionsVault.setEpochManager(address)._epochManagerAddress](src/CollectionsVault.sol#L157) is not in mixedCase

src/CollectionsVault.sol#L157


 - [ ] ID-169
Function [SimpleMockCToken._setComptrollerFee(uint256)](src/mocks/SimpleMockCToken.sol#L417-L423) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L417-L423


 - [ ] ID-170
Function [CTokenInterface._setInterestRateModel(InterestRateModel)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L230) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L230


 - [ ] ID-171
Function [CTokenInterface._acceptAdmin()](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L226) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L226


 - [ ] ID-172
Function [SimpleMockCToken._setAdminFee(uint256)](src/mocks/SimpleMockCToken.sol#L409-L415) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L409-L415


 - [ ] ID-173
Constant [OwnableUpgradeable.OwnableStorageLocation](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L28) is not in UPPER_CASE_WITH_UNDERSCORES

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L28


 - [ ] ID-174
Function [CTokenInterface._setComptroller(ComptrollerInterface)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L227) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L227


 - [ ] ID-175
Function [SimpleMockCToken._reduceReserves(uint256)](src/mocks/SimpleMockCToken.sol#L377-L384) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L377-L384


 - [ ] ID-176
Function [ReentrancyGuardUpgradeable.__ReentrancyGuard_init_unchained()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L64-L67) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L64-L67


 - [ ] ID-177
Function [CErc20Interface._addReserves(uint256)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L256) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L256


 - [ ] ID-178
Function [ICollectionsVault.ADMIN_ROLE()](src/interfaces/ICollectionsVault.sol#L104) is not in mixedCase

src/interfaces/ICollectionsVault.sol#L104


 - [ ] ID-179
Function [SimpleMockCToken._setComptroller(ComptrollerInterface)](src/mocks/SimpleMockCToken.sol#L360-L366) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L360-L366


 - [ ] ID-180
Function [OwnableUpgradeable.__Ownable_init(address)](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L51-L53) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L51-L53


 - [ ] ID-181
Function [CTokenInterface._setPendingAdmin(address)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L225) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L225


 - [ ] ID-182
Function [CDelegatorInterface._setImplementation(address,bool,bytes)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L278) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L278


 - [ ] ID-183
Parameter [MockFeeOnTransferERC20.setFeeCollector(address)._newFeeCollector](src/mocks/MockFeeOnTransferERC20.sol#L97) is not in mixedCase

src/mocks/MockFeeOnTransferERC20.sol#L97


 - [ ] ID-184
Function [OwnableUpgradeable.__Ownable_init_unchained(address)](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L55-L60) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/access/OwnableUpgradeable.sol#L55-L60


 - [ ] ID-185
Function [SimpleMockCToken._acceptAdmin()](src/mocks/SimpleMockCToken.sol#L346-L358) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L346-L358


 - [ ] ID-186
Function [CTokenInterface._reduceReserves(uint256)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L229) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L229


 - [ ] ID-187
Constant [CTokenStorage.reserveFactorMaxMantissa](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L34) is not in UPPER_CASE_WITH_UNDERSCORES

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L34


 - [ ] ID-188
Function [ReentrancyGuardUpgradeable.__ReentrancyGuard_init()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L60-L62) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L60-L62


 - [ ] ID-189
Function [ContextUpgradeable.__Context_init_unchained()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L21-L22) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L21-L22


 - [ ] ID-190
Function [CDelegateInterface._becomeImplementation(bytes)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L287) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L287


 - [ ] ID-191
Parameter [MockFeeOnTransferERC20.setFeeBpsSend(uint16)._newFeeBps](src/mocks/MockFeeOnTransferERC20.sol#L87) is not in mixedCase
INFO:Slither:. analyzed (73 contracts with 100 detectors), 224 result(s) found

src/mocks/MockFeeOnTransferERC20.sol#L87


 - [ ] ID-192
Parameter [CollectionsVault.setDebtSubsidizer(address)._debtSubsidizerAddress](src/CollectionsVault.sol#L162) is not in mixedCase

src/CollectionsVault.sol#L162


 - [ ] ID-193
Function [SimpleMockCToken._setPendingAdmin(address)](src/mocks/SimpleMockCToken.sol#L338-L344) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L338-L344


 - [ ] ID-194
Function [SimpleMockCToken._addReserves(uint256)](src/mocks/SimpleMockCToken.sol#L400-L406) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L400-L406


 - [ ] ID-195
Constant [ReentrancyGuardUpgradeable.ReentrancyGuardStorageLocation](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L47) is not in UPPER_CASE_WITH_UNDERSCORES

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol#L47


 - [ ] ID-196
Parameter [CollectionsVault.setLendingManager(address)._lendingManagerAddress](src/CollectionsVault.sol#L140) is not in mixedCase

src/CollectionsVault.sol#L140


 - [ ] ID-197
Function [PausableUpgradeable.__Pausable_init()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L77-L78) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L77-L78


 - [ ] ID-198
Function [ContextUpgradeable.__Context_init()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L18-L19) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol#L18-L19


 - [ ] ID-199
Function [SimpleMockCToken._setReserveFactor(uint256)](src/mocks/SimpleMockCToken.sol#L368-L375) is not in mixedCase

src/mocks/SimpleMockCToken.sol#L368-L375


 - [ ] ID-200
Function [CTokenInterface._setReserveFactor(uint256)](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L228) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L228


 - [ ] ID-201
Constant [PausableUpgradeable.PausableStorageLocation](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L25) is not in UPPER_CASE_WITH_UNDERSCORES

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L25


 - [ ] ID-202
Function [PausableUpgradeable.__Pausable_init_unchained()](dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L80-L81) is not in mixedCase

dependencies/@openzeppelin-contracts-upgradeable-5.3.0/utils/PausableUpgradeable.sol#L80-L81


 - [ ] ID-203
Function [CDelegateInterface._resignImplementation()](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L292) is not in mixedCase

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L292


## redundant-statements
Impact: Informational
Confidence: High
 - [ ] ID-204
Redundant expression "[accrualResult](src/LendingManager.sol#L258)" in[LendingManager](src/LendingManager.sol#L19-L390)

src/LendingManager.sol#L258


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-205
[Math.log2(uint256)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L612-L651) uses literals with too many digits:
	- [r = r | byte(uint256,uint256)(x >> r,0x0000010102020202030303030303030300000000000000000000000000000000)](dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L649)

dependencies/@openzeppelin-contracts-5.3.0/utils/math/Math.sol#L612-L651


## unused-state
Impact: Informational
Confidence: High
 - [ ] ID-206
[DebtSubsidizer.MAX_YIELD_SHARE_PERCENTAGE](src/DebtSubsidizer.sol#L40) is never used in [DebtSubsidizer](src/DebtSubsidizer.sol#L26-L262)

src/DebtSubsidizer.sol#L40


 - [ ] ID-207
[DebtSubsidizer.MIN_YIELD_SHARE_PERCENTAGE](src/DebtSubsidizer.sol#L41) is never used in [DebtSubsidizer](src/DebtSubsidizer.sol#L26-L262)

src/DebtSubsidizer.sol#L41


 - [ ] ID-208
[DebtSubsidizer._userSecondsClaimed](src/DebtSubsidizer.sol#L48) is never used in [DebtSubsidizer](src/DebtSubsidizer.sol#L26-L262)

src/DebtSubsidizer.sol#L48


 - [ ] ID-209
[CTokenStorage.borrowRateMaxMantissa](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L31) is never used in [SimpleMockCToken](src/mocks/SimpleMockCToken.sol#L20-L424)

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L31


 - [ ] ID-210
[LendingManager.PRECISION](src/LendingManager.sol#L27) is never used in [LendingManager](src/LendingManager.sol#L19-L390)

src/LendingManager.sol#L27


 - [ ] ID-211
[CTokenStorage.reserveFactorMaxMantissa](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L34) is never used in [SimpleMockCToken](src/mocks/SimpleMockCToken.sol#L20-L424)

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L34


## immutable-states
Impact: Optimization
Confidence: High
 - [ ] ID-212
[CollectionsVault.collectionRegistry](src/CollectionsVault.sol#L34) should be immutable 

src/CollectionsVault.sol#L34


 - [ ] ID-213
[CTokenStorage.initialExchangeRateMantissa](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L57) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L57


 - [ ] ID-214
[CTokenStorage.accrualBlockNumber](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L67) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L67


 - [ ] ID-215
[CErc20Storage.underlying](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L237) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L237


 - [ ] ID-216
[CTokenStorage.totalBorrows](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L77) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L77


 - [ ] ID-217
[CTokenStorage.borrowIndex](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L72) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L72


 - [ ] ID-218
[CTokenStorage._notEntered](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L13) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L13


 - [ ] ID-219
[MockERC20._customDecimals](src/mocks/MockERC20.sol#L12) should be immutable 

src/mocks/MockERC20.sol#L12


 - [ ] ID-220
[MockFeeOnTransferERC20._mockDecimals](src/mocks/MockFeeOnTransferERC20.sol#L11) should be immutable 

src/mocks/MockFeeOnTransferERC20.sol#L11


 - [ ] ID-221
[CTokenStorage.decimals](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L28) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L28


 - [ ] ID-222
[CTokenStorage.totalReserves](dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L82) should be immutable 

dependencies/compound-protocol-2.8.1/contracts/CTokenInterfaces.sol#L82


## var-read-using-this
Impact: Optimization
Confidence: High
 - [ ] ID-223
The function [MockERC721.mintSpecific(address,uint256)](src/mocks/MockERC721.sol#L36-L50) reads [this.ownerOf(tokenId)](src/mocks/MockERC721.sol#L39-L44) with `this` which adds an extra STATICCALL.

src/mocks/MockERC721.sol#L36-L50


