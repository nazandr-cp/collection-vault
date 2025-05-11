	•	Подготовка окружения
	•	Добавить RPC ApeChain и Curtis Testnet в конфигурацию (Foundry/Hardhat/Truffle)
	•	Убедиться, что доступны системные контракты:
	•	ArbInfo @ 0x0000000000000000000000000000000000000065
	•	ArbOwnerPublic @ 0x000000000000000000000000000000000000006b
	•	Интерфейсы контрактов

interface IArbInfo {
    function configureDelegateYield(address delegate) external;
    function configureAutomaticYield() external;
    function configureVoidYield() external;
}

interface IArbOwnerPublic {
    function getApy() external view returns (uint256);
    function getSharePrice() external view returns (uint256);
}


	•	Реализация Minimal Proxy Wrapper
	•	Написать контракт APEDelegateWrapper.sol с функциями:
	•	initialize(address user)
	•	deposit(uint256 amount)
	•	withdraw(uint256 amount)
	•	В initialize вызывать:

IArbInfo(arbInfo).configureDelegateYield(user);


	•	В deposit и withdraw реализовать логику перевода $APE и учёта баланса
	•	Добавить onlyOwner/initializer модификаторы (OpenZeppelin Initializable)

	•	Контракт пула
	•	Подключить библиотеку Clones (OpenZeppelin)
	•	При deposit(user, amount):
	1.	Создать новый прокси с Clones.clone(wrapperImpl)
	2.	Вызвать initialize(user) у прокси
	3.	Перевести amount APE на адрес прокси
	4.	Сохранить wrapper в mapping(address => address[]) userWrappers
	•	При withdraw(user, wrapperIndex):
	1.	Получить адрес прокси из userWrappers
	2.	Вызвать у него withdraw(amount)
	3.	Перевести APE обратно пользователю
	4.	Опционально: уничтожить прокси (если нужно)
	•	UI / Backend
	•	Реализовать фронт:
	•	Форма депозита APE
	•	Отображение списка wrapper адресов и балансов (через eth_getBalanceValues)
	•	Кнопка withdraw, вызывающая withdraw в пуле
	•	Настроить подписку на события Deposit / Withdraw
	•	Тестирование
	•	Написать unit-тесты:
	•	Проверка configureDelegateYield в initialize
	•	Депозит/ребейс: баланс прокси увеличивается при sharePrice тике
	•	Вывод средств и пересчёт
	•	Интеграционные тесты на Curtis Testnet
	•	Оптимизация и безопасность
	•	Провести аудит gas-расходов
	•	Проверить корректность работы при смене режима Void / Automatic
	•	Защитить от re-entrancy (ReentrancyGuard)
	•	Обработать edge-cases: мульти-депозиты, частичные вывода
	•	Документация
	•	Описать схему в README
	•	Привести примеры вызовов RPC:

cast rpc --rpc-url https://rpc.apechain.com eth_getBalanceValues <wrapperAddr> latest


	•	Добавить диаграмму потока (Опционально)

	•	Деплой
	•	Деплой APEDelegateWrapper и LendingPool на Curtis Testnet
	•	Проверить все сценарии
	•	Деплой на Mainnet ApeChain