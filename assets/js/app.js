import React from 'react'
import ReactDOM from 'react-dom'
import { AppProvider } from '@shopify/polaris'
import enTranslations from '@shopify/polaris/locales/en.json'
import '@shopify/polaris/styles.css'

import ShowPlans from './components/show-plans'
import ExternalRedirect from './components/external-redirect'

window.WrappedShowPlans = (props) => {
  return ReactDOM.render(
    <AppProvider i18n={enTranslations}>
      <ShowPlans
        plans={props.plans}
        guard={props.guard}
        shopUrl={props.shop_url}
        redirectAfter={props.redirect_after}
        shopifyApiKey={props.shopify_api_key}
        sessionToken={props.session_token}
      />
    </AppProvider>,
    document.getElementById("root")
  )
}

window.WrappedRedirect = ({
  shop_url, shopify_api_key, redirect_location
}) => {
  return ReactDOM.render(
    <AppProvider i18n={enTranslations}>
      <ExternalRedirect shopUrl={shop_url} shopifyApiKey={shopify_api_key} redirectLocation={redirect_location} />
    </AppProvider>,
    document.getElementById("root")
  );
}