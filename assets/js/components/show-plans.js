import React, { Component } from 'react'
import {
    Card,
    Page,
    List,
    Layout
} from '@shopify/polaris'
import axios from 'axios'
import createApp from '@shopify/app-bridge'
import { Redirect } from '@shopify/app-bridge/actions'

export default class ShowPlans extends React.Component {
    constructor(props) {
        super(props)
        const app = createApp({
            apiKey: props.shopifyApiKey,
            shopOrigin: props.shopUrl,
        })
        const redirect = Redirect.create(app);
        this.state = {redirect: redirect}
    }

    selectPlan(plan) {
        let csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        axios.post
            (
                "/payment/select-plan",
                {
                    plan_id: plan.id,
                    redirect_after: this.props.redirectAfter
                },
                {
                    headers: { "x-csrf-token": csrfToken }
                }
            )
            .then(resp => {
                this.state.redirect.dispatch(Redirect.Action.REMOTE, resp.data.recurring_application_charge.confirmation_url)
            })
    }

    render() {
        let cards = []
        for (let i = 0; i < this.props.plans.length; i++) {
            let plan = this.props.plans[i]
            let features = []
            for (let j = 0; j < plan.features.length; j++) {
                let feature = plan.features[j]
                features.push(<List.Item key={"card" + i + "list" + j}>{feature}</List.Item>)
            }
            cards.push(
                <Layout.Section oneThird key={"card" + i}>
                    <Card
                        title={`${plan.name}`}
                        primaryFooterAction={{
                            content: 'Select',
                            loading: this.loading,
                            onClick: () => {
                                this.loading = true
                                this.selectPlan(plan)
                            }
                        }}
                    >
                        <Card.Section>
                            <h1 style={{ fontSize: "30px", marginBottom: "25px" }}>${plan.price}/month</h1>
                            <List>
                                {features}
                            </List>
                        </Card.Section>
                    </Card>
                </Layout.Section>
            )
        }
        return <Page
            fullWidth
            title="Payment required to access this feature"
        >
            <Layout>
                {cards}
            </Layout>
        </Page>;
    }
}