import logging

def before_all(context):
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
