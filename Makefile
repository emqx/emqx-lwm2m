PROJECT = emqx_lwm2m
PROJECT_DESCRIPTION = EMQ X LwM2M Gateway
PROJECT_VERSION = 3.0

NO_AUTOPATCH = cuttlefish

DEPS = lwm2m_coap jsx clique
dep_lwm2m_coap = git-emqx https://github.com/emqx/lwm2m-coap v1.0.0
dep_jsx        = git-emqx https://github.com/talentdeficit/jsx v2.9.0
dep_clique     = git-emqx https://github.com/emqx/clique develop

BUILD_DEPS = emqx cuttlefish
dep_emqx = git-emqx https://github.com/emqx/emqx emqx30
dep_cuttlefish = git-emqx https://github.com/emqx/cuttlefish emqx30

TEST_DEPS = emqttc
dep_emqttc = git-emqx https://github.com/emqtt/emqttc master

ERLC_OPTS += +debug_info

define dep_fetch_git-emqx
	git clone -q --depth 1 -b $(call dep_commit,$(1)) -- $(call dep_repo,$(1)) $(DEPS_DIR)/$(call dep_name,$(1)) > /dev/null 2>&1; \
	cd $(DEPS_DIR)/$(call dep_name,$(1));
endef

include erlang.mk

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emqx_lwm2m.conf -i priv/emqx_lwm2m.schema -d data
