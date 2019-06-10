# ansible-tower-utilities
Shell script tools to assist the population of Tower for software defined environment

*wf_generator.sh*
This script is useful where multiple job templates need to be sequentially applied to a target inventory.
It takes advantage of Tower workflows to automatically create a single workflow that is comprised of a list of multiple job templates.
Command line args allow for the final workflow template to be flexibly constructed for either maximum customisation by the user, by constructing an uber survey from the union of the individual job template surverys, or by extracting the default values from the sub job template surveys and embedding them in the new workflow template. The latter allows the new workflow to be called via the API from the source of the users choice. In my case, from Vsphere VRa, for customization of newly built virtual hosts.
Command line also allows a target inventory to be specified for the new workflow, or by not passing an inventory, the user is free to select both survey values and inventory at the point the workflow is launched.
