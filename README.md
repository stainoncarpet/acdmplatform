# Advanced Sample Hardhat Project

This project demonstrates an advanced Hardhat use case, integrating other tools commonly used alongside Hardhat in the ecosystem.

The project comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts. It also comes with a variety of other tools, preconfigured to work with the project code.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
REPORT_GAS=true npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.ts
TS_NODE_FILES=true npx ts-node scripts/deploy.ts
npx eslint '**/*.{js,ts}'
npx eslint '**/*.{js,ts}' --fix
npx prettier '**/*.{json,sol,md}' --check
npx prettier '**/*.{json,sol,md}' --write
npx solhint 'contracts/**/*.sol'
npx solhint 'contracts/**/*.sol' --fix
```

# Etherscan verification

To try out Etherscan verification, you first need to deploy a contract to an Ethereum network that's supported by Etherscan, such as Ropsten.

In this project, copy the .env.example file to a file named .env, and then edit it to fill in the details. Enter your Etherscan API key, your Ropsten node URL (eg from Alchemy), and the private key of the account which will send the deployment transaction. With a valid .env file in place, first deploy your contract:

```shell
hardhat run --network ropsten scripts/deploy.ts
```

Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:

```shell
npx hardhat verify --network ropsten DEPLOYED_CONTRACT_ADDRESS "Hello, Hardhat!"
```

# Performance optimizations

For faster runs of your tests and scripts, consider skipping ts-node's type checking by setting the environment variable `TS_NODE_TRANSPILE_ONLY` to `1` in hardhat's environment. For more details see [the documentation](https://hardhat.org/guides/typescript.html#performance-optimizations).

# ТЗ площадка для продажи ACDM 

-Написать смарт контракт ACDMPlatform
-Написать полноценные тесты к контракту
-Написать скрипт деплоя
-Задеплоить в тестовую сеть
-Написать таск на на основные методы
-Верифицировать контракт

Есть 2 раунда «Торговля» и «Продажа», которые следуют друг за другом, начиная с раунда продажи.
Каждый раунд длится 3 дня.

Основные понятия:
Раунд «Sale» - В данном раунде пользователь может купить токены ACDM по фиксируемой цене у платформы за ETH.
Раунд «Trade» - в данном раунде пользователи могут выкупать друг у друга токены ACDM за ETH.
Реферальная программа — реферальная программа имеет два уровня, пользователи получают реварды в ETH.

Описание раунда «Sale»:
Цена токена с каждым раундом растет и рассчитывается по формуле. Количество выпущенных токенов в каждом Sale раунде разное и зависит от общего объема торгов в раунде «Trade». Раунд может закончиться досрочно если все токены были распроданы. По окончанию раунда не распроданные токены сжигаются. Самый первый раунд продает токенны на сумму 1ETH (100 000 ACDM)
Пример расчета:
объем торгов в trade раунде = 0,5 ETH (общая сумма ETH на которую пользователи наторговали в рамках одного trade раунд)
0,5 / 0,0000187 = 26737.96. (0,0000187 = цена токена в текущем раунде)
следовательно в Sale раунде будет доступно к продаже 26737.96 токенов ACDM.

Описание раунда «Trade»:
user_1 выставляет ордер на продажу ACDM токенов за определенную сумму в ETH. User_2 выкупает токены за ETH. Ордер может быть выкуплен не полностью. Также ордер можно отозвать и пользователю вернутся его токены, которые еще не были проданы. Полученные ETH сразу отправляются пользователю в их кошелек metamask. По окончанию раунда все открытые ордера закрываются и оставшиеся токены отправляются их владельцам.

Описание Реферальной программы:
-При регистрации пользователь указывает своего реферера (Реферер должен быть уже зарегистрирован на платформе).
-При покупке в Sale раунде токенов ACDM, рефереру_1 отправится 5% от его покупки, рефереру_2 отправится 3%, сама платформа получит 92% в случае отсутствия рефереров всё получает платформа.
-При покупке в Trade раунде пользователь, который выставил ордер на продажу ACDM токенов получит 95% ETH и по 2,5% получат рефереры, в случае их отсутствия платформа забирает эти проценты себе.

Price ETH = lastPrice*1,03+0,000004
Пример расчета цены токена: 0,0000100*1,03+0,000004 = 0,0000143
Sale Round N	Price ETH
            1	0,00001
            2	0,0000143
            3	0,0000187
            4	0,0000233
            5	0,000028
            6	0,0000328