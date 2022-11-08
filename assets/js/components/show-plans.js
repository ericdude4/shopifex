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
        this.state = { redirect: redirect }
    }

    selectPlan(plan) {
        axios.post
            (
                this.props.planSelectRoute,
                {
                    plan_id: plan.id,
                    redirect_after: this.props.redirectAfter,
                    token: this.props.sessionToken
                }
            )
            .then(resp => {
                this.state.redirect.dispatch(Redirect.Action.REMOTE, resp.data.confirmation_url)
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
                <div style={{ minWidth: '250px', maxWidth: '350px', marginRight: '10px' }} key={"card" + i}>
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
                            <h1 style={{ fontSize: "30px", marginBottom: "25px" }}>${plan.price}{plan.type === "recurring_application_charge" ? "/month" : " one time payment"}</h1>
                            <List>
                                {features}
                            </List>
                        </Card.Section>
                    </Card>
                </div>
            )
        }

        return <Page
            fullWidth
            title="Payment options"
            secondaryActions={[{
                content: "Back",
                onAction: () => { history.back(); }
            }]}
        >
            <p>Select a plan to continue</p>
            <div style={{ padding: '20px' }}>
                <div style={{ display: 'flex', maxWidth: "100%" }}>
                    {cards}
                </div>
            </div>
        </Page>;
    }
}