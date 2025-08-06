import asyncio
import aiohttp
import ssl
import pulumi

from urllib.parse import urljoin
from jsonrpc_websocket import Server


config = pulumi.Config("xenorchestra")
xo_url = config.require("url")

# PLEASE READ:
#
# Calling require instead of require_secret is not ideal
# as we lose the secret tag of the token value, potentially
# exposing it in clear.
# This is done because I didn't manage to get async and
# pulumi.Output.apply working together in order to pass the
# token value to session.signInWithToken.
# Probably a skill issue ...
xo_token = config.require("token")


async def set_memory_and_restart(args: pulumi.ResourceHookArgs):
    """Call XO's JSON-RPC API to set static memory values"""

    outputs = args.new_outputs

    if outputs is None:
        raise ValueError("No outputs from hook set_memory")

    vm_id = outputs["id"]
    vm_memory = outputs.get("memoryMax", 2 * 1024 * 1024 * 1024)

    # Wait for the initial cloudinit execution to complete
    await asyncio.sleep(90)

    # If you need to ignore certificate validation, create an explicit context for it
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    # Ideallly, ClientSession should be persistent for the program lifetime
    # as it manages a connection pool. Recreating it every time is wasteful
    # but it will do fine for managing a few VMs.
    async with aiohttp.ClientSession(
        connector=aiohttp.TCPConnector(ssl=context),
    ) as aioclient:
        api_url = urljoin(base=xo_url, url="/api/")
        rpcserver = Server(api_url, aioclient)

        try:
            await rpcserver.ws_connect()
            await rpcserver.session.signInWithToken(token=xo_token)

            rpc_args = {
                "id": vm_id,
                "memory": vm_memory,
                "memoryMin": vm_memory,
                "memoryMax": vm_memory,
                "memoryStaticMax": vm_memory,
            }
            await rpcserver.vm.setAndRestart(**rpc_args)

        finally:
            await rpcserver.close()
