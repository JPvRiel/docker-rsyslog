import logging
import time


def before_all(context):
    logging.info("sleeping to provide 2 seconds grace time for services to become available before testing")
    time.sleep(2)
    # to improve, rather check/vaildate syslog server has been running with open ports
    # for @wip (-w), set DEBUG level logging handler
    if not context.config.log_capture:
        logging.basicConfig(level=logging.DEBUG)


def before_feature(context, feature):
    if "skip" in feature.tags:
        feature.skip("Feature tagged with @skip")
        return


def before_scenario(context, scenario):
    if "skip" in scenario.effective_tags:
        scenario.skip("Scenario tagged with @skip")
        return
