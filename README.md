# HelloID-Conn-Prov-Source-Daywize


| :information_source: Information                                                                                                                                                                                                                                                                                                                                                       |
| :------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.personeelensalaris.nl/wp-content/uploads/2019/06/daywizelogo-rgb-300x116.jpg">
</p>

## Table of contents

- [HelloID-Conn-Prov-Source-Daywize](#helloid-conn-prov-source-daywize)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
    - [Endpoints](#endpoints)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
      - [Contracts](#contracts)
      - [API](#api)
      - [Filtering](#filtering)
      - [Departments](#departments)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

*HelloID-Conn-Prov-Source-Daywize* is a source connector designed to import all relevant person and contract data for Identity Access Management. Its purpose is to populate persons in HelloID.
### Endpoints

Currently the following endpoints are being used..

| Endpoint                                           |
| -------------------------------------------------- |
| odata/POS_Provisioning/Medewerker_SamenvattingList |
| /odata/POS_Provisioning/ContractList               |
| /odata/POS_Provisioning/FormatieList               |
| /odata/POS_Provisioning/SD_AfdelingList            |



> The API documentation can be found at the URl below. <br>
> [Daywize Documentation: Content for Provisioning](https://daywize-test.mendixcloud.com/odata-doc/POS_Provisioning).


## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting        | Description                        | Mandatory |
| -------------- | ---------------------------------- | --------- |
| Username       | The Username to connect to the API | Yes       |
| Password       | The Password to connect to the API | Yes       |
| BaseUrl        | The URL to the API                 | Yes       |


### Remarks
#### Contracts
The connector creates a HelloID contract for each formation and enriches the Daywize formation with the contract and department information. The Daywize contract can be seen as the employment contract."


#### API
There is a possibility to limit API responses using $select to reduce the data returned for each web request, but this is not currently implemented. <br>
Not every person or contract contains the used expanded fields. To avoid errors in HelloID mapping, the connector flattens the objects.


#### Filtering
The connector does not filter out inactive persons, as there is no API parameter available to do this. You could add a custom filter in the persons.ps1 script to achieve the same result.


#### Departments
- The department script filters imports only active departments.
- The managers are determined based on the departments. A few departments have multiple managers, and in such cases, the manager with the lowest employee number is chosen.
- In addition to the above, the connector requires HelloID's manager calculation based on departments.
  - [Primary manager determinant](https://docs.helloid.com/en/provisioning/persons/contracts/departments/managers--provisioning-.html)
- The `ExternalId` used is `AutoID_Afdeling`, because the `code` or `CodeExternal` field is not always populated with a value.




## Getting help

> ℹ️ _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012557600-Configure-a-custom-PowerShell-source-system) pages_

> ℹ️ _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/5176-helloid-provisioning-source-inplanning)

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
