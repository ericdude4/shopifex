import "react-phoenix"

import React from 'react'
// import ReactDOM from 'react-dom'
import { AppProvider } from '@shopify/polaris'
import enTranslations from '@shopify/polaris/locales/en.json'
import '@shopify/polaris/styles.css'

import ShowPlans from './components/show-plans'
import LoadSession from './components/load-session'

function WrappedLoadSession(props) {
  return (
    <AppProvider i18n={enTranslations}>
      <LoadSession shopUrl={props.shop_url} redirectAfter={props.redirect_after} shopifyApiKey={props.shopify_api_key} />
    </AppProvider>
  )
}

function WrappedShowPlans(props) {
  return (
    <AppProvider i18n={enTranslations}>
      <ShowPlans plans={props.plans} guard={props.guard} shopUrl={props.shop_url} redirectAfter={props.redirect_after} shopifyApiKey={props.shopify_api_key} />
    </AppProvider>
  )
}

window.Components = {
  WrappedShowPlans,
  WrappedLoadSession
}