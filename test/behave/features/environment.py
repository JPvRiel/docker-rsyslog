import logging
import time


BEHAVE_DEBUG_ON_ERROR = False


def setup_debug_on_error(userdata):
  global BEHAVE_DEBUG_ON_ERROR
  BEHAVE_DEBUG_ON_ERROR = userdata.getbool('BEHAVE_DEBUG_ON_ERROR')


def before_all(context):
  setup_debug_on_error(context.config.userdata)
  logging.info('Sleeping to provide 2 seconds grace time for services to become available before testing')
  time.sleep(2)
  # to improve, rather check/vaildate syslog server has been running with open ports
  # for @wip (-w), set DEBUG level logging handler
  if not context.config.log_capture:
    logging.basicConfig(level=logging.DEBUG)


def before_feature(context, feature):
  if 'skip' in feature.tags:
    feature.skip('Feature tagged with @skip.')
    return


def before_scenario(context, scenario):
  if 'skip' in scenario.effective_tags:
    scenario.skip('Scenario tagged with @skip.')
    return
  # create a default empty dict to track env vars we want in context
  context.env = {}


def after_step(context, step):
  if BEHAVE_DEBUG_ON_ERROR and step.status == 'failed':
    logging.info(f'Running debugger for failed scenario {context.scenario.name} and step {step.name}.')
    import pdb
    pdb.post_mortem(step.exc_traceback)
