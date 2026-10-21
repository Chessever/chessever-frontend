import base64
import json
import unittest
from validate_client_config import PROJECT, validate


def fixture_key(role='anon', project=PROJECT):
    payload = base64.urlsafe_b64encode(json.dumps({'role': role, 'ref': project}).encode()).decode().rstrip('=')
    return f'e30.{payload}.fixture'


class PublicClientConfigurationTest(unittest.TestCase):
    def config(self, key=None):
        return {'SUPABASE_URL': f'https://{PROJECT}.supabase.co',
                'SUPABASE_ANON_KEY': key or fixture_key(), 'REVENUECAT_API_KEY': 'appl_public_fixture'}

    def test_public_production_keys_pass(self):
        validate(self.config(), mobile=True)
        validate(self.config('sb_publishable_public_fixture'))

    def test_server_and_wrong_project_keys_are_rejected(self):
        for key in (fixture_key('service_role'), fixture_key(project='another-project'),
                    'sb_secret_server_fixture', 'sbp_management_fixture', 'not-a-key'):
            with self.subTest(key_type=key.split('_')[0]):
                with self.assertRaises(ValueError): validate(self.config(key))

    def test_private_sdk_admin_key_and_wrong_target_are_rejected(self):
        config = self.config()
        config['REVENUECAT_API_KEY'] = 'sk_admin_fixture'
        with self.assertRaises(ValueError): validate(config, mobile=True)
        config = self.config()
        config['SUPABASE_URL'] = 'https://another-project.supabase.co'
        with self.assertRaises(ValueError): validate(config)


if __name__ == '__main__':
    unittest.main()
