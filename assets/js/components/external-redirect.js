import React, { useEffect } from 'react';
import createApp from '@shopify/app-bridge';
import { Redirect } from '@shopify/app-bridge/actions';
import { Frame, TextContainer, Layout, Page } from '@shopify/polaris'

export default function ExternalRedirect({ shopUrl, shopifyApiKey, redirectLocation }) {
  const app = createApp({
    apiKey: shopifyApiKey,
    shopOrigin: shopUrl,
  });

  const redirect = Redirect.create(app);

  const doRedirect = () => {
    if (window.self == window.top) {
      // do a normal redirect if not in an iFrame
      window.location = redirectLocation
    } else {
      redirect.dispatch(Redirect.Action.REMOTE, redirectLocation)
    }
  }

  useEffect(() => {
    doRedirect()
  }, [])

  return (
    <Page title="You are being redirected">
      <Layout>
        <Layout.Section>
          <Frame>
            <TextContainer style="padding-top: 3 rem;">
              <p>
                If you are not automatically redirected within 5 seconds, &nbsp;
                <a href="#" onClick={doRedirect}>click here</a>
              </p>
            </TextContainer>
          </Frame>
        </Layout.Section>
      </Layout>
    </Page>
  );
}
