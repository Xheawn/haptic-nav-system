from pyicloud import PyiCloudService
import sys
from Point import Point

# 亲测有效,平均一秒一次
# 在室内定位很不准确,所以到时候演示可能要从室外开始

def login(account: str, password: str) -> PyiCloudService :
    """
    登陆,注意不能是国区,而且商店和设置的账号得要一样。
    """
    api = PyiCloudService(account, password)

    # 假设需要双验证,我们把让用户输入双验证的密码。
    if api.requires_2fa:
        print("Two-factor authentication required.")
        code = input("Enter the code you received of one of your approved devices: ")
        result = api.validate_2fa_code(code)
        print("Code validation result: %s" % result)

        if not result:
            print("Failed to verify security code")
            sys.exit(1)

        if not api.is_trusted_session:
            print("Session is not trusted. Requesting trust...")
            result = api.trust_session()
            print("Session trust result %s" % result)

            if not result:
                print("Failed to request trust. You will likely be prompted for the code again in the coming weeks")
    elif api.requires_2sa:
        import click
        print("Two-step authentication required. Your trusted devices are:")

        devices = api.trusted_devices
        for i, device in enumerate(devices):
            print(
                "  %s: %s" % (i, device.get('deviceName',
                "SMS to %s" % device.get('phoneNumber')))
            )

        device = click.prompt('Which device would you like to use?', default=0)
        device = devices[device]
        if not api.send_verification_code(device):
            print("Failed to send verification code")
            sys.exit(1)

        code = click.prompt('Please enter validation code')
        if not api.validate_verification_code(device, code):
            print("Failed to verify verification code")
            sys.exit(1)
    return api

def get_curr_location(api: PyiCloudService) -> Point:
    loc = api.devices[3].location()
    return Point(-1, loc['latitude'], loc['longitude'])

