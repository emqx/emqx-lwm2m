
emqx_lwm2m
==========

LWM2M Gateway for the EMQ X Broker

LWM2M is Lightweight Machine to Machine protocol. Its standard can be found [here](http://www.openmobilealliance.org/release/LightweightM2M).

User is able to send LWM2M commands(READ/WRITE/EXECUTE/...) and get LWM2M response in mqtt way. emqx_lwm2m transforms data between mqtt and LWM2M protocol.

emqx_lwm2m needs object definitions to parse data from lwm2m devices. Object definitions are declared by organisitions in XML format, you can find those XMLs [here](http://www.openmobilealliance.org/wp/OMNA/LwM2M/LwM2MRegistry.html). Please download required XMLs and put them into directory specified by lwm2m.xml_dir. If no associated object definition is found, response from device will be discarded and report an error message in system log.


Configure Plugin
----------------

File: etc/emqx_lwm2m.conf

```
lwm2m.port = 5783
lwm2m.certfile = etc/certs/cert.pem
lwm2m.keyfile = etc/certs/key.pem
lwm2m.xml_dir =  etc/lwm2m_xml
```
- lwm2m.port
  + UDP port for coap. The secured port will be (lwm2m.port+1).
- lwm2m.certfile
  + server certificate for DTLS
- lwm2m.keyfile
  + private key for DTLS
- lwm2m.xml_dir
  + a directory to store XML files.

Load Plugin
-----------

```
./bin/emqx_ctl plugins load emqx_lwm2m
```

# mqtt topics

- Downlink command topic is "lwm2m/{?device_end_point_name}/command".
- Uplink response topic is "lwm2m/{?device_end_point_name}/response".

# mqtt payload

## READ command

Downlink message payload

```
{
    "CmdID": {?CmdID},
    "Command": "Read",
    "BaseName": {?BaseName}
}
```
- {?CmdId} is an integer to pair command and response.
- {?BaseName} is a string identify object and resource, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.

Uplink Response payload

```
{
    "CmdID": {?CmdID},
    "Command": "Read",
    "Result": {?JsonValue}
}
```
or

```
{
    "CmdID": {?CmdID},
    "Command": "Read",
    "Error": {?Error}
}
```
- {?CmdId} is an integer to pair command and response.
- {?JsonValue} is the json presentation of LWM2M data, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.
- {?Error} is a string, please refer to error code.


## WRITE command

Downlink command payload

```
{
    "CmdID": {?CmdID},
    "Command": "Write",
    "Value": {?JsonValue}
}
```
- {?CmdID}, an integer to identify a command response against its request.
- {?JsonValue} is the json presentation of LWM2M data, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.


Uplink response payload

```
{
    "CmdID": {?CmdID},
    "Command": "Write",
    "Result": {?Code}
}
```

or

```
{
    "CmdID": {?CmdID},
    "Command": "Write",
    "Error": {?Code}
}
```
- {?CmdID}, an integer to identify a command response against its request.
- {?Code} could be "Changed", "Bad Request", "Not Found", "Unauthorized" or "Method Not Allowed"


## EXECUTE command

Downlink message payload

```
{
    "CmdID": {?CmdID},
    "Command": "Execute",
    "BaseName": {?BaseName},
    "Arguments": {?Args}
}
```
- {?CmdId} is an integer to pair command and response.
- {?BaseName} is a string identify object and resource, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.
- {?Args} is a string. Please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.5 Execute.

Uplink Response payload

```
{
    "CmdID": {?CmdID},
    "Command": "Execute",
    "Result": "Changed"
}
```
or

```
{
    "CmdID": {?CmdID},
    "Command": "Execute",
    "Error": {?Error}
}
```
- {?CmdId} is an integer to pair command and response.
- {?Error} is a string, please refer to error code.


## DISCOVER command

Downlink command payload

```
{
    "CmdID": {?CmdID},
    "Command": "Discover",
    "BaseName": {?BaseName}
}
```
- {?CmdID}, an integer to identify a command response against its request.
- {?BaseName} is a string identify object and resource, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.


Uplink response payload

```
{
    "CmdID": {?CmdID},
    "Command": "Discover",
    "Result": {?Link}
}
```

or

```
{
    "CmdID": {?CmdID},
    "Command": "Discover",
    "Error": {?Code}
}
```
- {?CmdID} is an integer to identify a command response against its request.
- {?Link} is a list of application/link-format CoRE Links. Please refer to  OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 5.4.2 Discover.
- {?Code} could be "Bad Request", "Not Found", "Unauthorized" or "Method Not Allowed"


## WRITE-ATTRIBUTE command

Downlink command payload

```
{
    "CmdID": {?CmdID},
    "Command": "Write-Attributes",
    "BaseName": {?BaseName},
    "Value": {?Value}
}
```
- {?CmdID}, an integer to identify a command response against its request.
- {?BaseName} is a string identify object and resource, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.
- {?Value} is a string in following format:

```
pmin={minimum_period}&pmax={maximum_period}&gt={greater_than}&lt={less_than}&st={step}
```
All attributes are optional.


Uplink response payload

```
{
    "CmdID": {?CmdID},
    "Command": "Write-Attributes",
    "Result": {?Code}
}
```

or

```
{
    "CmdID": {?CmdID},
    "Command": "Write-Attributes",
    "Error": {?Code}
}
```
- {?CmdID}, an integer to identify a command response against its request.
- {?Code} could be "Changed", "Bad Request", "Not Found", "Unauthorized" or "Method Not Allowed"


## OBSERVE command

Downlink message payload

```
{
    "CmdID": {?CmdID},
    "Command": "Observe",
    "BaseName": {?BaseName}
}
```
- {?CmdId} is an integer to pair command and response.
- {?BaseName} is a string identify object and resource, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.

Uplink Response payload

```
{
    "CmdID": {?CmdID},
    "Command": "Observe",
    "Result": {?JsonValue}
}
```
or

```
{
    "CmdID": {?CmdID},
    "Command": "Observe",
    "Error": {?Error}
}
```
- {?CmdId} is an integer to pair command and response.
- {?JsonValue} is the json presentation of LWM2M data, please refer to OMA-TS-LightweightM2M-V1_0-20170208-A.pdf section 6.4.4 JSON.
- {?Error} is a string, please refer to error code.


## Error Code

- "Not Acceptable"
- "Method Not Allowed"
- "Not Found"
- "Unauthorized"
- "Bad Request"
- "No XML Definition"


## NOTES
- emqx_lwm2m implements LWM2M server, which does not include LWM2M bootstrap server. 
- emqx_lwm2m supports UDP binding, no SMS binding yet.
- emqx_lwm2m does not support 
- Fireware object is not fully supported now since mqtt to coap blockwise transfer is not available.
- Object Versioning is not supported now.


DTLS
-----------
emqx-lwm2m support DTLS to secure UDP data.

Please config lwm2m.certfile and lwm2m.keyfile in emqx_lwm2m.conf. If certfile or keyfile are invalid, DTLS will be turned off and you could read a error message in system log.

## Client
wakaama is an easy-to-read lwm2m client tool.


Download source code:

```
git clone https://github.com/eclipse/wakaama
```

Modify wakaama/examples/lightclient/object_security.c, replace uri with appropriate value:

```
targetP->uri = strdup("coap://localhost:5783");
```

Compile wakaama:

```
mkdir build_wakaama
cd build_wakaama 
cmake -DCMAKE_BUILD_TYPE=Debug ../wakaama/examples/lightclient 
make
```

Run

```
build_wakaama/lightclient -4 -n testclient
```


License
-------

Apache License Version 2.0


Author
------

EMQ X-Men Team.

