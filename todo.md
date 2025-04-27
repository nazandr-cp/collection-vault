Sure! Here’s a clean technical specification for the lazy evaluation reward scaling mechanism:

⸻

Technical Specification: Lazy Evaluation Reward Scaling for MVP

Objective

Implement a dynamic reward distribution mechanism that automatically adjusts user rewards based on the actual yield available in the system, ensuring that total payouts do not exceed the available budget. The mechanism should be scalable, predictable, and avoid hardcoded limits on reward coefficients such as beta or baseRewardRate. No deficit should accumulate in user state.

⸻

Key Concepts
	•	Epoch-based Budgeting:
Rewards are distributed in discrete periods (epochs). At the start of each new epoch, a reward budget is calculated based on a fixed share (e.g., 60%) of the lending yield accrued during the previous epoch.
	•	Global Scaling Factor:
The system maintains a global scaling factor per epoch that adjusts the calculated user rewards proportionally. This ensures that total payouts never exceed the available budget.
	•	Lazy Initialization:
The scaling factor is not precomputed. It is established on the first user claim in each epoch based on the calculated raw reward for that user and the total available yield. Once set, the scaling factor remains constant for the entire epoch.

⸻

Functional Requirements
	1.	Epoch Management
	•	Define a fixed epoch duration (e.g., 1 day).
	•	Track the last epoch timestamp and last global reward index (e.g., the cToken exchange rate at the start of the epoch).
	2.	Budget Calculation
	•	On the first claim of a new epoch, calculate the yield accrued since the last epoch (the difference between the current lending index and the previous index).
	•	Compute the reward budget as a fixed percentage (e.g., 60%) of the accrued yield.
	3.	Scaling Factor Calculation (Lazy Evaluation)
	•	For the first claimant in the new epoch:
	•	Calculate their raw, unscaled reward using the existing reward logic (including NFT bonuses).
	•	Derive the global scaling factor as:

scaling factor = reward budget / raw reward of first claimant


	•	Cap the scaling factor to 1.0 (i.e., no scaling if the budget exceeds the raw reward).

	•	Store the scaling factor for use in all subsequent claims during the same epoch.

	4.	Reward Calculation
	•	For each claim (including the first):
	•	Calculate the raw reward using existing logic.
	•	Apply the global scaling factor to derive the final adjusted reward:

final reward = raw reward * scaling factor


	5.	Preview Functionality
	•	Ensure that the previewRewards function uses the current scaling factor to present accurate, capped rewards to users.
	•	If the epoch has not been initialized (no scaling factor exists yet), return an estimated scaling factor of 1.0 for preview purposes.
	6.	Edge Case Handling
	•	If no yield has been accrued in the lending strategy during the epoch, the reward budget is zero, and all rewards are scaled to zero for that epoch.
	•	Prevent division by zero or invalid scaling factor calculations.
	7.	Upgradeability
	•	Ensure compatibility with the existing upgradeable contract pattern.
	•	Leave storage gaps where necessary for future extensions.

⸻

Non-Functional Requirements
	•	Gas Efficiency:
The mechanism should not require looping through users or collections for budget or scaling factor computation. All calculations must be based on the first claim trigger for each epoch.
	•	Transparency & Debugging:
	•	Emit events on each epoch rollover, budget calculation, and scaling factor initialization, providing visibility into the system’s internal state.
	•	Optionally, include logging during reward calculations for auditability.
	•	Flexibility:
The reward share percentage and epoch duration should be configurable via admin functions.

⸻

Deliverables
	•	Smart contract implementation of the lazy reward scaling mechanism.
	•	Unit tests covering:
	•	Correct scaling factor computation.
	•	Reward adjustment across multiple users in the same epoch.
	•	Handling of edge cases (zero yield, early previews).
	•	Integration with existing RewardsController contract logic.
	•	Updated documentation for reward calculation and claiming.

⸻

Let me know if you’d like to tweak or expand on anything!