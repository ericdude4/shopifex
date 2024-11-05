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

        let app;
        let redirect;

        try {
            app = createApp({
                apiKey: props.shopifyApiKey,
                host: props.shopifyHost,
            })
            redirect = Redirect.create(app);
        } catch (error) {
            redirect = {
                dispatch: (action, url) => {
                    window.location.href = url;
                }
            }
        }

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
        let currentGrants = this.props.currentGrants.split(",")

        const arraysContainSameElements = (arr1, arr2) => {
            // First, check if the arrays have the same length
            if (arr1.length !== arr2.length) {
                return false;
            }

            // Sort both arrays and join them into strings for easy comparison
            const sortedArr1 = arr1.slice().sort();
            const sortedArr2 = arr2.slice().sort();

            // Compare each element in the sorted arrays
            for (let i = 0; i < sortedArr1.length; i++) {
                if (sortedArr1[i] !== sortedArr2[i]) {
                    return false;
                }
            }

            return true;
        }

        let cards = []
        for (let i = 0; i < this.props.plans.length; i++) {
            let plan = this.props.plans[i]
            let features = []
            for (let j = 0; j < plan.features.length; j++) {
                let feature = plan.features[j]
                features.push(<List.Item key={"card" + i + "list" + j}>{feature}</List.Item>)
            }

            // The plan is considered the current plan if the same set of grants exist in the store
            let isCurrentPlan = arraysContainSameElements(currentGrants, plan.grants)

            cards.push(
                <div style={{ width: '250px', marginRight: '10px' }} key={"card" + i}>
                    <Card
                        title={`${plan.name}`}
                        primaryFooterAction={{
                            content: isCurrentPlan ? 'Current plan' : 'Select',
                            disabled: isCurrentPlan,
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