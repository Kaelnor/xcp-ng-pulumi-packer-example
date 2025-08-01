import pulumi
import pulumi_random as prandom


def generate_xen_mac(name: str) -> pulumi.Output[str]:
    """Generate a random mac address starting with the XenSource OUI"""

    random_bytes_hex = prandom.RandomBytes(name, length=3).hex
    generated_mac = pulumi.Output.concat(
        "00:16:3e:",
        random_bytes_hex[0:2],
        ":",
        random_bytes_hex[2:4],
        ":",
        random_bytes_hex[4:6],
    )
    return generated_mac
