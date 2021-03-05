import React, { Component } from 'react'
import {
    Page,
    Layout
} from '@shopify/polaris'
import createApp from '@shopify/app-bridge'
import { getSessionToken } from "@shopify/app-bridge-utils";

export default class LoadSession extends React.Component {
    constructor(props) {
        super(props)
        const app = createApp({
            apiKey: props.shopifyApiKey,
            shopOrigin: props.shopUrl
        })
        this.state = { app: app }
    }

    componentDidMount() {
        console.log(this.state)
        getSessionToken(this.state.app).then((sessionToken) => {
            console.log("Shopifex loaded session JWT", sessionToken)
            console.log("Redirecting to requested page...", this.props.redirectAfter + "session_token=" + sessionToken)
            window.location = this.props.redirectAfter + "session_token=" + sessionToken
        }).catch(error => {
            console.error(error)
        });
    }


    render() {
        return <Page
            fullWidth
            title="Loading"
        >
        </Page>;
    }
}