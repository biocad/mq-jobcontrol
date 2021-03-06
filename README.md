# mq-jobcontrol
Component for interactions with Monique via interface.

## Назначение

Компонент jobcontrol предоставляет пользователю возможность отправлять в Monique сообщения и проверять, что система будет их корректно обрабатывать.

Взаимодействие с пользователем на данный момент происходит посредством терминала.

## Конфигурация

Jobcontrol является компонентом Monique, общающимся с самой очередью исключительно через "одно место" (Scheduler).
В силу этого в config.json указываются параметры только для "одного места". 

Все остальные поля являются стандартными как для любого другого компонента системы.

## Сборка и запуск

Сборка производится с помощью инструмента [stack](https://docs.haskellstack.org/en/stable/README/):

```
stack build
```

Запуск компонента производится командой

```
stack exec mq-jobcontrol
```

## Использование

После запуска компонента в терминале откроется окно ввода, с помощью которого можно посылать сообщения в Monique.

Пользователю доступны три команды:

* **run** позволяет отправить сообщение в очередь;
* **help run** позволяет посмотреть, какие аргументы принимает на вход команда **run**;
* **help** выводит список всех доступных команд с их описанием.

### run

Команда **run** принимает четыре аргумента в следующем порядке:

* **spec** отправляемого сообщения;
* тип отправляемого сообщения: config, result, data или error;
* тип кодировки содержимого поля **data** отправляемого сообщения: JSON или MessagePack;
* путь до файла, содержащего в соответствующем формате информацию, которая будет отправлена в поле **data**.

## Логика работы

После того, как пользователь запустил команду **run**, из переданных в неё аргументов формируется сообщение и отправляется в очередь.

Компонент jobcontrol подписывается на любые сообщения из очереди, в поле **pid** которых будет стоять **id**, сгенерироанный для отправленного сообщения.

Если полученное таким образом сообщение в свою очередь порождает другие сообщения, то jobcontrol подписывается и на такие сообщения тоже.

## Примеры

Ниже приведены команды для запуска стандартных примеров для компонентов.

Считается, что к этому моменту запущено "одно место" а также те компоненты, которые мы хотим протестировать.

### Пример "калькулятор"

Запустить задачу для калькулятора можно следующей командой из терминала jobcontrol:

```
run example_calculator config JSON test/calculator.json
```

### Пример "банк"

Запустить задачу для банка можно следующей командой из терминала jobcontrol:

```
run example_bank config JSON test/bank.json
```




