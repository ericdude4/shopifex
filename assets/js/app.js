import React from 'react'
import ReactDOM from 'react-dom'
import { AppProvider } from '@shopify/polaris'
import enTranslations from '@shopify/polaris/locales/en.json'
import '@shopify/polaris/build/esm/styles.css'

import ShowPlans from './components/show-plans'
import ExternalRedirect from './components/external-redirect'

window.WrappedShowPlans = (props) => {
  return ReactDOM.render(
    <AppProvider i18n={enTranslations}>
      <ShowPlans
        plans={props.plans}
        guard={props.guard}
        redirectAfter={props.redirect_after}
        shopifyApiKey={props.shopify_api_key}
        shopifyHost={props.shopify_host}
        sessionToken={props.session_token}
        planSelectRoute={props.plan_select_route}
        currentGrants={props.current_grants}
      />
    </AppProvider>,
    document.getElementById("root")
  )
}

window.WrappedRedirect = ({
  shopify_host, shopify_api_key, redirect_location, message
}) => {
  return ReactDOM.render(
    <AppProvider i18n={enTranslations}>
      <ExternalRedirect shopifyHost={shopify_host} shopifyApiKey={shopify_api_key} redirectLocation={redirect_location} message={message} />
    </AppProvider>,
    document.getElementById("root")
  );
}