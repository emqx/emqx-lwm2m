PROJECT = emqx_lwm2m
PROJECT_DESCRIPTION = EMQ X LwM2M Gateway
PROJECT_VERSION = 3.0

NO_AUTOPATCH = cuttlefish

DEPS = lwm2m_coap jsx clique
dep_lwm2m_coap = git https://github.com/emqx/lwm2m-coap v1.0.0
dep_jsx        = git https://github.com/talentdeficit/jsx v2.9.0
dep_clique     = git https://github.com/emqx/clique

BUILD_DEPS = emqx cuttlefish
dep_emqx = git https://github.com/emqx/emqx emqx30
dep_cuttlefish = git https://github.com/emqx/cuttlefish emqx30

TEST_DEPS = emqttc
dep_emqttc = git https://github.com/emqtt/emqttc

ERLC_OPTS += +debug_info

include erlang.mk

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emqx_lwm2m.conf -i priv/emqx_lwm2m.schema -d data
